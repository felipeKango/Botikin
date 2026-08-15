import Foundation
import BotikinKit

// MARK: - Modelos de sesión

struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let userID: UUID
    let email: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case userID = "user_id"
        case email
    }
}

private struct AuthResponse: Decodable {
    struct Session: Decodable {
        let access_token: String
        let refresh_token: String
    }
    struct User: Decodable {
        let id: UUID
        let email: String?
    }
    let session: Session?
    let user: User?
}

// MARK: - SessionStore

/// Estado global de la app: sesión + token meter compartido.
/// Fuente de verdad del pill "⚡ 2k" visible en todas las pantallas.
@MainActor
final class SessionStore: ObservableObject {

    @Published private(set) var session: AuthSession?
    @Published private(set) var accountant: TokenAccountant?
    @Published var mostrarPaywall = false
    @Published var mensajePaywall = ""

    var estaAutenticado: Bool { session != nil }
    var accessToken: String? { session?.accessToken }

    private static let keychainKey = "auth_session"

    init() {
        if let data = KeychainStore.load(key: Self.keychainKey),
           let saved = try? JSONDecoder().decode(AuthSession.self, from: data) {
            session = saved
        }
    }

    // MARK: Autenticación (vía auth-api)

    func login(email: String, password: String) async throws {
        let response: AuthResponse = try await APIClient.shared.invoke(
            "auth-api",
            body: ["action": "login", "email": email, "password": password],
            accessToken: nil)
        try adoptar(response)
        await refrescarSuscripcion()
    }

    func registrar(nombre: String, email: String, password: String) async throws {
        let response: AuthResponse = try await APIClient.shared.invoke(
            "auth-api",
            body: ["action": "signup", "email": email,
                   "password": password, "nombre": nombre],
            accessToken: nil)
        try adoptar(response)
        await refrescarSuscripcion()
    }

    func cerrarSesion() {
        session = nil
        accountant = nil
        KeychainStore.delete(key: Self.keychainKey)
    }

    private func adoptar(_ response: AuthResponse) throws {
        guard let s = response.session, let u = response.user else {
            throw APIError.servidor(codigo: "no_session",
                                    mensaje: "El servidor no entregó una sesión.")
        }
        let auth = AuthSession(accessToken: s.access_token,
                               refreshToken: s.refresh_token,
                               userID: u.id, email: u.email ?? "")
        session = auth
        if let data = try? JSONEncoder().encode(auth) {
            KeychainStore.save(data, key: Self.keychainKey)
        }
    }

    /// Reintenta con refresh token cuando el access token expiró.
    func refrescarSesion() async {
        guard let refresh = session?.refreshToken else { return }
        do {
            let response: AuthResponse = try await APIClient.shared.invoke(
                "auth-api",
                body: ["action": "refresh", "refresh_token": refresh],
                accessToken: nil)
            try adoptar(response)
        } catch {
            cerrarSesion()
        }
    }

    // MARK: Token meter compartido

    func refrescarSuscripcion() async {
        guard let token = accessToken else { return }
        do {
            let subs: [Subscription] = try await APIClient.shared.select(
                "subscriptions",
                query: [URLQueryItem(
                    name: "select",
                    value: "plan,estado,tokens_total,tokens_usados,fecha_renovacion,codigo_descuento_usado")],
                accessToken: token)
            if let sub = subs.first {
                accountant = TokenAccountant(subscription: sub)
            }
        } catch APIError.sesionExpirada {
            await refrescarSesion()
        } catch {
            // El meter mantiene el último valor conocido; no bloquea la UI.
        }
    }

    /// Las respuestas de ai-engine/notif-api traen tokens_restantes:
    /// actualiza el pill sin otra vuelta al servidor.
    func sincronizarTokens(restantes: Int?) {
        guard let restantes, var acc = accountant else { return }
        acc.sincronizar(tokensRestantes: restantes)
        accountant = acc
    }

    /// Manejo centralizado del bloqueo del portero: muestra el paywall.
    func manejarBloqueo(_ error: Error) -> Bool {
        if let api = error as? APIError, api.invitaUpgrade {
            mensajePaywall = api.localizedDescription
            mostrarPaywall = true
            return true
        }
        return false
    }
}
