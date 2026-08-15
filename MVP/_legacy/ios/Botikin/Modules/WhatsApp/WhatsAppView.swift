import SwiftUI
import BotikinKit

struct WhatsAppView: View {
    @EnvironmentObject private var sesion: SessionStore
    @StateObject private var modelo = WhatsAppViewModel()
    @State private var mostrandoNuevo = false

    var body: some View {
        NavigationStack {
            Group {
                switch modelo.estado {
                case .inicial, .cargando:
                    ProgressView("Cargando mensajes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .error(let mensaje):
                    ErrorBanner(mensaje: mensaje) {
                        Task { await modelo.cargar(token: sesion.accessToken) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .listo:
                    contenido
                }
            }
            .navigationTitle("WhatsApp")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { TokenPill() }
            }
            .refreshable { await modelo.cargar(token: sesion.accessToken) }
            .task { await modelo.cargar(token: sesion.accessToken) }
            .sheet(isPresented: $mostrandoNuevo) {
                NuevoMensajeView(modelo: modelo)
            }
        }
    }

    private var contenido: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Button {
                        mostrandoNuevo = true
                    } label: {
                        Label("Nuevo mensaje", systemImage: "square.and.pencil")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.botikinVerde, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        modelo.alertasAuto.toggle()
                    } label: {
                        Label("Alertas auto", systemImage: "bolt.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Color.botikinNaranjo.opacity(modelo.alertasAuto ? 0.2 : 0.08),
                                in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(modelo.alertasAuto
                                ? Color.botikinNaranjo : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            }

            Section {
                if modelo.mensajes.isEmpty {
                    EmptyState(icono: "bubble.left.and.bubble.right",
                               titulo: "Sin mensajes aún",
                               mensaje: "Los recordatorios y alertas que envíes por WhatsApp aparecerán aquí")
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(modelo.mensajes) { mensaje in
                        WhatsAppMessageRow(mensaje: mensaje)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

struct WhatsAppMessageRow: View {
    let mensaje: WhatsAppMessage

    private var iconoTipo: String {
        switch mensaje.tipo {
        case .expiryAlert: "exclamationmark.triangle"
        case .reminder: "clock"
        case .aiSuggestion: "brain"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: iconoTipo)
                    .foregroundStyle(.secondary)
                Text(mensaje.tipo.nombre)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadge(texto: mensaje.estadoEntrega.nombre,
                            color: mensaje.estadoEntrega.color)
            }
            Text(mensaje.telefono)
                .font(.headline)
            Text(mensaje.texto)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Formato.fechaCorta(mensaje.createdAt))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Nuevo mensaje

struct NuevoMensajeView: View {
    @ObservedObject var modelo: WhatsAppViewModel
    @EnvironmentObject private var sesion: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var telefono = ""
    @State private var contexto = ""
    @State private var tipo: WhatsAppMessageType = .reminder

    private var valido: Bool {
        telefono.hasPrefix("+") && telefono.count >= 11 && !contexto.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Destinatario") {
                    TextField("+56912345678", text: $telefono)
                        .keyboardType(.phonePad)
                }
                Section("Tipo") {
                    Picker("Tipo de mensaje", selection: $tipo) {
                        ForEach(WhatsAppMessageType.allCases, id: \.self) {
                            Text($0.nombre).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    TextField(
                        "Ej: recuérdale a mamá tomar el Omeprazol 20mg en ayunas",
                        text: $contexto, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("¿Qué quieres recordar?")
                } footer: {
                    Label("La IA redactará el mensaje (~\(TokenAction.whatsappMessage.costo) tokens)",
                          systemImage: "bolt.fill")
                        .foregroundStyle(Color.botikinNaranjo)
                }
                if let error = modelo.errorEnvio {
                    Section {
                        Text(error).foregroundStyle(Color.botikinRojo)
                    }
                }
            }
            .navigationTitle("Nuevo mensaje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await modelo.enviar(telefono: telefono,
                                                   contexto: contexto,
                                                   tipo: tipo, sesion: sesion) {
                                dismiss()
                            }
                        }
                    } label: {
                        if modelo.enviando { ProgressView() } else { Text("Enviar") }
                    }
                    .disabled(!valido || modelo.enviando)
                }
            }
        }
    }
}
