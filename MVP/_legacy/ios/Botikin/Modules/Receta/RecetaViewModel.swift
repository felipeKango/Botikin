import Foundation
import UIKit
import BotikinKit

@MainActor
final class RecetaViewModel: ObservableObject {

    enum Fase: Equatable {
        case inicial
        case subiendo
        case analizando
        case listo
        case error(String)
    }

    @Published var imagen: UIImage?
    @Published var fase: Fase = .inicial
    @Published var resultado: PrescriptionAnalysis?
    @Published var tokensConsumidos = 0
    @Published var agregandoMedicamento: String?

    private let api = APIClient.shared

    private struct AIResponse: Decodable {
        let resultado: PrescriptionAnalysis
        let tokens_consumidos: Int
        let tokens_restantes: Int
    }

    var puedeAnalizar: Bool {
        imagen != nil && fase != .subiendo && fase != .analizando
    }

    /// Foto → Storage → fila en prescriptions → ai-engine (Claude Vision).
    func analizar(sesion: SessionStore) async {
        guard let imagen, let token = sesion.accessToken,
              let userID = sesion.session?.userID else { return }
        guard let jpeg = imagen.jpegData(compressionQuality: 0.7) else {
            fase = .error("No pudimos procesar la foto")
            return
        }

        resultado = nil
        fase = .subiendo
        do {
            // 1. Subir la foto al bucket privado (carpeta del usuario, RLS)
            let path = "\(userID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            _ = try await api.uploadStorage(
                bucket: "prescriptions", path: path, data: jpeg,
                contentType: "image/jpeg", accessToken: token)

            // 2. Registrar la receta
            struct Insert: Encodable {
                let user_id: UUID
                let foto_path: String
            }
            struct Row: Decodable { let id: UUID }
            let filas: [Row] = try await api.insert(
                "prescriptions",
                body: Insert(user_id: userID, foto_path: path),
                accessToken: token)
            guard let receta = filas.first else {
                throw APIError.decodificacion
            }

            // 3. Análisis con Claude (pasa por el portero de tokens)
            fase = .analizando
            let respuesta: AIResponse = try await api.invoke(
                "ai-engine",
                body: ["action": "analyze_prescription",
                       "prescription_id": receta.id.uuidString],
                accessToken: token)

            resultado = respuesta.resultado
            tokensConsumidos = respuesta.tokens_consumidos
            sesion.sincronizarTokens(restantes: respuesta.tokens_restantes)
            fase = .listo
        } catch {
            if sesion.manejarBloqueo(error) {
                fase = .inicial
            } else {
                fase = .error(error.localizedDescription)
            }
        }
    }

    /// Agrega al botiquín un medicamento marcado "Comprar".
    func agregarAlBotiquin(_ med: PrescriptionMedicine, sesion: SessionStore) async {
        guard let token = sesion.accessToken,
              let userID = sesion.session?.userID else { return }
        agregandoMedicamento = med.id
        defer { agregandoMedicamento = nil }
        struct Insert: Encodable {
            let user_id: UUID
            let nombre: String
            let dosis: String
            let unidades: Int
            let fecha_vencimiento: Date
            let viene_de_receta: Bool
        }
        // Vencimiento por defecto: 1 año (el usuario lo ajusta al comprarlo)
        let vence = Calendar.current.date(byAdding: .year, value: 1, to: .now)!
        do {
            let _: [Medicine] = try await api.insert(
                "medicines",
                body: Insert(user_id: userID, nombre: med.nombre, dosis: med.dosis,
                             unidades: 0, fecha_vencimiento: vence,
                             viene_de_receta: true),
                accessToken: token)
            // Marca el medicamento como "ya lo tienes" en el resultado
            if var actual = resultado {
                actual.medicamentos = actual.medicamentos.map {
                    var m = $0
                    if m.id == med.id { m.yaLoTienes = true }
                    return m
                }
                resultado = actual
            }
        } catch {
            fase = .error(error.localizedDescription)
        }
    }

    func reiniciar() {
        imagen = nil
        resultado = nil
        fase = .inicial
    }
}
