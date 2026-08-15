import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var nombre = ""
    @Published var email = ""
    @Published var password = ""
    @Published var cargando = false
    @Published var error: String?

    var loginValido: Bool {
        email.contains("@") && password.count >= 6
    }
    var registroValido: Bool {
        !nombre.trimmingCharacters(in: .whitespaces).isEmpty && loginValido
    }

    func login(sesion: SessionStore) async {
        error = nil
        cargando = true
        defer { cargando = false }
        do {
            try await sesion.login(email: email, password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func registrar(sesion: SessionStore) async {
        error = nil
        cargando = true
        defer { cargando = false }
        do {
            try await sesion.registrar(nombre: nombre, email: email, password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
