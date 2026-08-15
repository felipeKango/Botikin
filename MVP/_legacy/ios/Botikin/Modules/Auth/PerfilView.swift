import SwiftUI

/// Perfil mínimo: teléfono (necesario para WhatsApp) y cierre de sesión.
struct PerfilView: View {
    @EnvironmentObject private var sesion: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var nombre = ""
    @State private var telefono = ""
    @State private var guardando = false
    @State private var mensaje: String?

    private struct Perfil: Decodable {
        let nombre: String
        let telefono: String?
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mis datos") {
                    TextField("Nombre", text: $nombre)
                    TextField("Teléfono WhatsApp (+56912345678)", text: $telefono)
                        .keyboardType(.phonePad)
                }
                Section {
                    Button {
                        Task { await guardar() }
                    } label: {
                        if guardando { ProgressView() } else { Text("Guardar cambios") }
                    }
                } footer: {
                    Text("El teléfono se usa para enviarte alertas por WhatsApp (planes Básico y Pro).")
                }
                if let mensaje {
                    Section { Text(mensaje).font(.footnote) }
                }
                Section {
                    Button("Cerrar sesión", role: .destructive) {
                        sesion.cerrarSesion()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Mi cuenta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task { await cargar() }
        }
    }

    private func cargar() async {
        guard let token = sesion.accessToken else { return }
        do {
            let perfiles: [Perfil] = try await APIClient.shared.select(
                "users",
                query: [URLQueryItem(name: "select", value: "nombre,telefono")],
                accessToken: token)
            if let p = perfiles.first {
                nombre = p.nombre
                telefono = p.telefono ?? ""
            }
        } catch {
            mensaje = error.localizedDescription
        }
    }

    private func guardar() async {
        guard let token = sesion.accessToken,
              let userID = sesion.session?.userID else { return }
        guardando = true
        defer { guardando = false }
        struct Update: Encodable {
            let nombre: String
            let telefono: String?
        }
        do {
            try await APIClient.shared.update(
                "users", id: userID,
                body: Update(nombre: nombre,
                             telefono: telefono.isEmpty ? nil : telefono),
                accessToken: token)
            mensaje = "Datos guardados ✓"
        } catch {
            mensaje = error.localizedDescription
        }
    }
}
