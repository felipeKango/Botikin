import Foundation
import BotikinKit

@MainActor
final class WhatsAppViewModel: ObservableObject {
    @Published var estado: Cargable<[WhatsAppMessage]> = .inicial
    @Published var alertasAuto = UserDefaults.standard.object(
        forKey: "alertas_auto") as? Bool ?? true {
        didSet { UserDefaults.standard.set(alertasAuto, forKey: "alertas_auto") }
    }
    @Published var enviando = false
    @Published var errorEnvio: String?

    private let api = APIClient.shared

    var mensajes: [WhatsAppMessage] { estado.valor ?? [] }

    func cargar(token: String?) async {
        guard let token else { return }
        if mensajes.isEmpty { estado = .cargando }
        do {
            let lista: [WhatsAppMessage] = try await api.select(
                "whatsapp_messages",
                query: [
                    URLQueryItem(name: "select",
                                 value: "id,telefono,texto,tipo,estado_entrega,created_at"),
                    URLQueryItem(name: "order", value: "created_at.desc"),
                    URLQueryItem(name: "limit", value: "100"),
                ],
                accessToken: token)
            estado = .listo(lista)
        } catch {
            if mensajes.isEmpty {
                estado = .error(error.localizedDescription)
            }
        }
    }

    /// Nuevo mensaje: Claude lo redacta (cobra tokens) y Twilio lo envía.
    func enviar(telefono: String, contexto: String,
                tipo: WhatsAppMessageType, sesion: SessionStore) async -> Bool {
        guard let token = sesion.accessToken else { return false }
        errorEnvio = nil
        enviando = true
        defer { enviando = false }

        struct Respuesta: Decodable {
            let enviado: Bool
            let tokens_restantes: Int?
        }
        do {
            let respuesta: Respuesta = try await api.invoke(
                "notif-api",
                body: ["action": "send_whatsapp",
                       "telefono": telefono,
                       "tipo": tipo.rawValue,
                       "contexto": contexto],
                accessToken: token)
            sesion.sincronizarTokens(restantes: respuesta.tokens_restantes)
            await cargar(token: token)
            return respuesta.enviado
        } catch {
            if !sesion.manejarBloqueo(error) {
                errorEnvio = error.localizedDescription
            }
            return false
        }
    }
}
