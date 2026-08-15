import Foundation

/// Estado de vencimiento de un remedio: el semáforo del botiquín.
public enum ExpiryStatus: Equatable, Sendable {
    case vencido(hace: Int)      // días desde el vencimiento
    case vencePronto(en: Int)    // vence en ≤ 7 días
    case venceEsteMes(en: Int)   // vence en 8–30 días
    case vigente(en: Int)        // más de 30 días

    public var etiqueta: String {
        switch self {
        case .vencido: "Vencido"
        case .vencePronto: "Vence pronto"
        case .venceEsteMes, .vigente: "Vigente"
        }
    }

    public var descripcion: String {
        switch self {
        case .vencido(let d): d == 0 ? "Venció hoy" : "Venció hace \(d)d"
        case .vencePronto(let d), .venceEsteMes(let d), .vigente(let d): "Vence en \(d)d"
        }
    }

    public var esUrgente: Bool {
        switch self {
        case .vencido, .vencePronto: true
        default: false
        }
    }
}

/// Filtros de la pantalla Mi Botiquín.
public enum ExpiryFilter: String, CaseIterable, Sendable {
    case todos = "Todos"
    case vencidos = "Vencidos"
    case urgente = "Urgente"
    case esteMes = "Este mes"
    case vigentes = "Vigentes"
}

public enum ExpiryCalculator {

    /// Días de calendario entre hoy y el vencimiento (negativo = vencido).
    public static func diasParaVencer(
        _ fechaVencimiento: Date,
        desde hoy: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let inicioHoy = calendar.startOfDay(for: hoy)
        let inicioVence = calendar.startOfDay(for: fechaVencimiento)
        return calendar.dateComponents([.day], from: inicioHoy, to: inicioVence).day ?? 0
    }

    public static func status(
        para fechaVencimiento: Date,
        desde hoy: Date = .now,
        calendar: Calendar = .current
    ) -> ExpiryStatus {
        let dias = diasParaVencer(fechaVencimiento, desde: hoy, calendar: calendar)
        switch dias {
        case ..<0: return .vencido(hace: -dias)
        case 0: return .vencido(hace: 0)
        case 1...7: return .vencePronto(en: dias)
        case 8...30: return .venceEsteMes(en: dias)
        default: return .vigente(en: dias)
        }
    }

    public static func filtrar(
        _ medicinas: [Medicine],
        por filtro: ExpiryFilter,
        desde hoy: Date = .now
    ) -> [Medicine] {
        medicinas.filter { med in
            let st = status(para: med.fechaVencimiento, desde: hoy)
            switch filtro {
            case .todos: return true
            case .vencidos: if case .vencido = st { return true } else { return false }
            case .urgente: return st.esUrgente
            case .esteMes: if case .venceEsteMes = st { return true } else { return false }
            case .vigentes:
                switch st {
                case .venceEsteMes, .vigente: return true
                default: return false
                }
            }
        }
    }

    /// Conteos para el banner de alerta ("1 vencido · 2 vencen en <7 días").
    public static func resumenAlertas(
        _ medicinas: [Medicine],
        desde hoy: Date = .now
    ) -> (vencidos: Int, porVencer: Int) {
        var vencidos = 0, porVencer = 0
        for med in medicinas {
            switch status(para: med.fechaVencimiento, desde: hoy) {
            case .vencido: vencidos += 1
            case .vencePronto: porVencer += 1
            default: break
            }
        }
        return (vencidos, porVencer)
    }
}
