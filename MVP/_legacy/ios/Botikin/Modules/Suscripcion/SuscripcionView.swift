import SwiftUI
import SafariServices
import BotikinKit

struct SuscripcionView: View {
    var mensajeBloqueo: String?

    @EnvironmentObject private var sesion: SessionStore
    @StateObject private var modelo = SuscripcionViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let mensajeBloqueo {
                    bannerBloqueo(mensajeBloqueo)
                }

                ForEach([Plan.free, .basic, .pro], id: \.self) { plan in
                    PlanCard(plan: plan,
                             actual: sesion.accountant?.subscription.plan == plan,
                             seleccionado: modelo.planSeleccionado == plan) {
                        if plan != .free { modelo.planSeleccionado = plan }
                    }
                }

                campoCodigo

                switch modelo.estado {
                case .exito(let mensaje):
                    resultado(mensaje, exito: true)
                case .fallo(let mensaje):
                    resultado(mensaje, exito: false)
                default:
                    PrimaryButton(
                        titulo: "Suscribirme al plan \(modelo.planSeleccionado.nombre)",
                        cargando: modelo.estado == .iniciandoPago
                            || modelo.estado == .esperandoWebPay) {
                        Task { await modelo.suscribirse(sesion: sesion) }
                    }
                    Text("Pago seguro con WebPay Plus (Transbank)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Elige tu plan")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cerrar") { dismiss() }
            }
        }
        // Checkout WebPay dentro de la app
        .sheet(isPresented: .init(
            get: { modelo.urlWebPay != nil },
            set: { if !$0 { modelo.urlWebPay = nil } })) {
            if let url = modelo.urlWebPay {
                SafariView(url: url).ignoresSafeArea()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .webpayResultado)) { note in
            guard let status = note.userInfo?["status"] as? String else { return }
            Task { await modelo.procesarResultadoWebPay(status, sesion: sesion) }
        }
    }

    private func bannerBloqueo(_ mensaje: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.slash.fill")
                .foregroundStyle(Color.botikinNaranjo)
            Text(mensaje)
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.botikinNaranjo.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private var campoCodigo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("¿Tienes un código de descuento?")
                .font(.subheadline.weight(.semibold))
            HStack {
                TextField("Ej: KANGO2026", text: $modelo.codigoDescuento)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                Button("Validar") {
                    Task { await modelo.validarCodigo(sesion: sesion) }
                }
                .buttonStyle(.bordered)
                .disabled(modelo.codigoDescuento.isEmpty
                    || modelo.estado == .validandoCodigo)
            }
            switch modelo.estado {
            case .validandoCodigo:
                ProgressView().padding(.top, 2)
            case .codigoValido(let meses):
                Label("Código válido: \(meses) mes(es) gratis",
                      systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.botikinVerde)
            case .codigoInvalido(let motivo):
                Label(motivo, systemImage: "xmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.botikinRojo)
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultado(_ mensaje: String, exito: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: exito ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(.system(size: 44))
                .foregroundStyle(exito ? Color.botikinVerde : Color.botikinRojo)
            Text(mensaje)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button(exito ? "Listo" : "Intentar de nuevo") {
                if exito { dismiss() } else { modelo.estado = .inicial }
            }
            .font(.headline)
            .foregroundStyle(Color.botikinPrimario)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Tarjeta de plan

struct PlanCard: View {
    let plan: Plan
    let actual: Bool
    let seleccionado: Bool
    let onTap: () -> Void

    private var detalles: [String] {
        switch plan {
        case .free:
            ["500 tokens (~5 análisis AI)", "Botiquín básico", "Sin WhatsApp"]
        case .basic:
            ["5.000 tokens (~50 análisis AI/mes)", "Análisis de recetas",
             "WhatsApp para ti"]
        case .pro:
            ["Tokens y análisis ilimitados", "WhatsApp para toda la familia",
             "Historial completo"]
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(plan.nombre)
                        .font(.title3.bold())
                    if actual {
                        StatusBadge(texto: "Tu plan", color: .botikinAzul)
                    }
                    Spacer()
                    if plan == .free {
                        Text("$0")
                            .font(.title3.bold())
                    } else {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(Formato.clp(plan.precioCLP))")
                                .font(.title3.bold())
                            Text("/mes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(detalles, id: \.self) { detalle in
                    Label(detalle, systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(seleccionado ? Color.botikinPrimario : Color(.systemGray5),
                        lineWidth: seleccionado ? 2 : 1))
        }
        .buttonStyle(.plain)
        .disabled(plan == .free)
    }
}

// MARK: - Safari para el checkout

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
