import Foundation
import BotikinKit

// MARK: - Evento del timeline

struct HistorialEvento: Identifiable, Equatable {
    enum Tipo: String, CaseIterable {
        case recetaEscaneada = "Receta escaneada"
        case analisisAI = "Análisis AI"
        case whatsappEnviado = "WhatsApp enviado"
        case remedioAgregado = "Remedio agregado"
    }

    let id: String
    let tipo: Tipo
    let titulo: String
    let detalle: String
    let fecha: Date
    let tokens: Int?
}

enum PeriodoHistorial: String, CaseIterable {
    case semana = "Esta semana"
    case mes = "Este mes"
    case tresMeses = "Últimos 3 meses"
    case todo = "Todo"

    var desde: Date? {
        let cal = Calendar.current
        switch self {
        case .semana: return cal.date(byAdding: .day, value: -7, to: .now)
        case .mes: return cal.date(byAdding: .month, value: -1, to: .now)
        case .tresMeses: return cal.date(byAdding: .month, value: -3, to: .now)
        case .todo: return nil
        }
    }
}

// MARK: - Estadísticas del resumen de salud

struct ResumenSalud: Equatable {
    var remediosActivos = 0
    var recetasEscaneadas = 0
    var analisisAI = 0
    var eventosDelMes = 0
    var vencidos = 0
    var tokensUsados = 0
}

@MainActor
final class HistorialViewModel: ObservableObject {
    @Published var estado: Cargable<[HistorialEvento]> = .inicial
    @Published var resumen = ResumenSalud()
    @Published var periodo: PeriodoHistorial = .mes
    @Published var filtroTipo: HistorialEvento.Tipo?

    private let api = APIClient.shared

    var eventosFiltrados: [HistorialEvento] {
        var lista = estado.valor ?? []
        if let desde = periodo.desde {
            lista = lista.filter { $0.fecha >= desde }
        }
        if let tipo = filtroTipo {
            lista = lista.filter { $0.tipo == tipo }
        }
        return lista.sorted { $0.fecha > $1.fecha }
    }

    /// Eventos agrupados por día: HOY / AYER / fecha.
    var eventosPorDia: [(titulo: String, eventos: [HistorialEvento])] {
        let cal = Calendar.current
        let grupos = Dictionary(grouping: eventosFiltrados) {
            cal.startOfDay(for: $0.fecha)
        }
        return grupos.keys.sorted(by: >).map { dia in
            let titulo: String
            if cal.isDateInToday(dia) { titulo = "HOY" }
            else if cal.isDateInYesterday(dia) { titulo = "AYER" }
            else { titulo = Formato.fechaLarga(dia).uppercased() }
            return (titulo, grupos[dia]!.sorted { $0.fecha > $1.fecha })
        }
    }

    /// Arma el historial cruzando las tablas del usuario (RLS filtra solo).
    func cargar(token: String?) async {
        guard let token else { return }
        if estado.valor == nil { estado = .cargando }
        do {
            async let recetasTask: [RecetaRow] = api.select(
                "prescriptions",
                query: [URLQueryItem(name: "select", value: "id,analysis,created_at"),
                        URLQueryItem(name: "order", value: "created_at.desc"),
                        URLQueryItem(name: "limit", value: "100")],
                accessToken: token)
            async let usosTask: [TokenUsageEntry] = api.select(
                "token_usage",
                query: [URLQueryItem(name: "select",
                                     value: "id,tipo_accion,tokens_consumidos,created_at"),
                        URLQueryItem(name: "order", value: "created_at.desc"),
                        URLQueryItem(name: "limit", value: "200")],
                accessToken: token)
            async let mensajesTask: [WhatsAppMessage] = api.select(
                "whatsapp_messages",
                query: [URLQueryItem(name: "select",
                                     value: "id,telefono,texto,tipo,estado_entrega,created_at"),
                        URLQueryItem(name: "order", value: "created_at.desc"),
                        URLQueryItem(name: "limit", value: "100")],
                accessToken: token)
            async let medicinasTask: [MedicinaRow] = api.select(
                "medicines",
                query: [URLQueryItem(name: "select",
                                     value: "id,nombre,dosis,fecha_vencimiento,created_at"),
                        URLQueryItem(name: "order", value: "created_at.desc")],
                accessToken: token)

            let (recetas, usos, mensajes, medicinas) =
                try await (recetasTask, usosTask, mensajesTask, medicinasTask)

            var eventos: [HistorialEvento] = []

            for receta in recetas {
                let meds = receta.analysis?.medicamentos
                    .map { "\($0.nombre) \($0.dosis)" }
                    .joined(separator: ", ") ?? "Sin análisis"
                let medico = receta.analysis?.medico ?? ""
                eventos.append(HistorialEvento(
                    id: "rx-\(receta.id)",
                    tipo: .recetaEscaneada,
                    titulo: "Receta analizada",
                    detalle: medico.isEmpty ? meds : "\(meds) — \(medico)",
                    fecha: receta.createdAt,
                    tokens: TokenAction.prescriptionAnalysis.costo))
            }
            for uso in usos where uso.tipoAccion != .prescriptionAnalysis {
                eventos.append(HistorialEvento(
                    id: "tk-\(uso.id)",
                    tipo: .analisisAI,
                    titulo: uso.tipoAccion.nombre,
                    detalle: "\(Formato.miles(uso.tokensConsumidos)) tokens",
                    fecha: uso.createdAt,
                    tokens: uso.tokensConsumidos))
            }
            for mensaje in mensajes {
                eventos.append(HistorialEvento(
                    id: "wa-\(mensaje.id)",
                    tipo: .whatsappEnviado,
                    titulo: "\(mensaje.tipo.nombre) enviada",
                    detalle: "\(mensaje.texto.prefix(80)) → \(mensaje.telefono)",
                    fecha: mensaje.createdAt,
                    tokens: nil))
            }
            for medicina in medicinas {
                eventos.append(HistorialEvento(
                    id: "med-\(medicina.id)",
                    tipo: .remedioAgregado,
                    titulo: "Remedio agregado",
                    detalle: "\(medicina.nombre) \(medicina.dosis)",
                    fecha: medicina.createdAt,
                    tokens: nil))
            }

            // Resumen de salud
            let cal = Calendar.current
            let inicioMes = cal.date(byAdding: .month, value: -1, to: .now)!
            let hoy = Date()
            var r = ResumenSalud()
            r.remediosActivos = medicinas.filter { $0.fechaVencimiento >= hoy }.count
            r.vencidos = medicinas.count - r.remediosActivos
            r.recetasEscaneadas = recetas.count
            r.analisisAI = usos.count
            r.eventosDelMes = eventos.filter { $0.fecha >= inicioMes }.count
            r.tokensUsados = usos.reduce(0) { $0 + $1.tokensConsumidos }
            resumen = r

            estado = .listo(eventos)
        } catch {
            if estado.valor == nil {
                estado = .error(error.localizedDescription)
            }
        }
    }

    // Filas auxiliares de decodificación
    private struct RecetaRow: Decodable {
        let id: UUID
        let analysis: PrescriptionAnalysis?
        let createdAt: Date
        enum CodingKeys: String, CodingKey {
            case id, analysis
            case createdAt = "created_at"
        }
    }

    private struct MedicinaRow: Decodable {
        let id: UUID
        let nombre: String
        let dosis: String
        let fechaVencimiento: Date
        let createdAt: Date
        enum CodingKeys: String, CodingKey {
            case id, nombre, dosis
            case fechaVencimiento = "fecha_vencimiento"
            case createdAt = "created_at"
        }
    }
}
