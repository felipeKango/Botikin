import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var sesion: SessionStore
    @StateObject private var modelo = AuthViewModel()
    @State private var mostrandoRegistro = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.botikinPrimario)
                        Text("Botikin")
                            .font(.largeTitle.bold())
                        Text("Tu botiquín familiar, inteligente")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 60)

                    VStack(spacing: 14) {
                        TextField("Correo electrónico", text: $modelo.email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Contraseña", text: $modelo.password)
                            .textContentType(.password)
                    }
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 4)
                    .modifier(CamposFormulario())

                    if let error = modelo.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color.botikinRojo)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PrimaryButton(titulo: "Iniciar sesión",
                                  cargando: modelo.cargando,
                                  deshabilitado: !modelo.loginValido) {
                        Task { await modelo.login(sesion: sesion) }
                    }

                    Button("¿No tienes cuenta? Regístrate") {
                        mostrandoRegistro = true
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal, 24)
            }
            .navigationDestination(isPresented: $mostrandoRegistro) {
                RegisterView()
            }
        }
    }
}

struct RegisterView: View {
    @EnvironmentObject private var sesion: SessionStore
    @StateObject private var modelo = AuthViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    TextField("Nombre", text: $modelo.nombre)
                        .textContentType(.name)
                    TextField("Correo electrónico", text: $modelo.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Contraseña (mínimo 6 caracteres)", text: $modelo.password)
                        .textContentType(.newPassword)
                }
                .textFieldStyle(.plain)
                .padding(.horizontal, 4)
                .modifier(CamposFormulario())
                .padding(.top, 24)

                if let error = modelo.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Color.botikinRojo)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                PrimaryButton(titulo: "Crear cuenta",
                              cargando: modelo.cargando,
                              deshabilitado: !modelo.registroValido) {
                    Task { await modelo.registrar(sesion: sesion) }
                }

                Text("Al crear tu cuenta partes con el plan Gratis: 500 tokens de IA al mes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle("Crear cuenta")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// Estilo compartido de los campos: tarjeta gris con esquinas redondeadas.
struct CamposFormulario: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }
}
