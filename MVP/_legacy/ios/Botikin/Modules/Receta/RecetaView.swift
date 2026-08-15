import SwiftUI
import PhotosUI
import BotikinKit

struct RecetaView: View {
    @EnvironmentObject private var sesion: SessionStore
    @StateObject private var modelo = RecetaViewModel()
    @State private var seleccionGaleria: PhotosPickerItem?
    @State private var mostrandoCamara = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    zonaFoto
                    botonesCaptura

                    PrimaryButton(
                        titulo: modelo.fase == .analizando
                            ? "Analizando con IA…" : "Analizar receta",
                        cargando: modelo.fase == .subiendo || modelo.fase == .analizando,
                        deshabilitado: !modelo.puedeAnalizar
                    ) {
                        Task { await modelo.analizar(sesion: sesion) }
                    }
                    .padding(.horizontal, 40)

                    if case .error(let mensaje) = modelo.fase {
                        ErrorBanner(mensaje: mensaje) {
                            Task { await modelo.analizar(sesion: sesion) }
                        }
                    }

                    if let resultado = modelo.resultado {
                        RecetaResultCard(
                            analisis: resultado,
                            tokens: modelo.tokensConsumidos,
                            agregando: modelo.agregandoMedicamento
                        ) { med in
                            Task { await modelo.agregarAlBotiquin(med, sesion: sesion) }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Receta")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { TokenPill() }
                if modelo.imagen != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Limpiar") { modelo.reiniciar() }
                    }
                }
            }
            .onChange(of: seleccionGaleria) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let imagen = UIImage(data: data) {
                        modelo.imagen = imagen
                        modelo.resultado = nil
                        modelo.fase = .inicial
                    }
                }
            }
            .fullScreenCover(isPresented: $mostrandoCamara) {
                CameraPicker { imagen in
                    modelo.imagen = imagen
                    modelo.resultado = nil
                    modelo.fase = .inicial
                }
                .ignoresSafeArea()
            }
        }
    }

    private var zonaFoto: some View {
        Group {
            if let imagen = modelo.imagen {
                Image(uiImage: imagen)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Fotografía tu receta médica y la IA\nla leerá por ti")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }
        }
    }

    private var botonesCaptura: some View {
        HStack(spacing: 12) {
            Button {
                mostrandoCamara = true
            } label: {
                Label("Cámara", systemImage: "camera.fill")
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Color.botikinPrimario, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            PhotosPicker(selection: $seleccionGaleria, matching: .images) {
                Text("Galería")
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Color.botikinPrimario.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.botikinPrimario)
            }
        }
    }
}

// MARK: - Tarjeta de resultado

struct RecetaResultCard: View {
    let analisis: PrescriptionAnalysis
    let tokens: Int
    let agregando: String?
    let onComprar: (PrescriptionMedicine) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.botikinVerde)
                Text("Receta analizada")
                    .font(.headline)
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                    Text(Formato.miles(tokens))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.botikinNaranjo)
            }

            filaDato("Médico", analisis.medico.isEmpty ? "No identificado" : analisis.medico)
            if let fecha = analisis.fechaReceta, !fecha.isEmpty {
                filaDato("Fecha receta", fecha)
            }

            Text("Medicamentos prescritos (\(analisis.medicamentos.count))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(analisis.medicamentos) { med in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: med.yaLoTienes
                            ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(med.yaLoTienes
                                ? Color.botikinVerde : Color.botikinRojo)
                        Text("\(med.nombre) \(med.dosis)")
                            .font(.headline)
                        Spacer()
                        if !med.yaLoTienes {
                            Button {
                                onComprar(med)
                            } label: {
                                if agregando == med.id {
                                    ProgressView()
                                } else {
                                    StatusBadge(texto: "Comprar", color: .botikinNaranjo)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !med.posologia.isEmpty {
                        Text(med.posologia)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !med.indicaciones.isEmpty {
                        Text(med.indicaciones)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                if med.id != analisis.medicamentos.last?.id { Divider() }
            }
        }
        .padding()
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.botikinVerde.opacity(0.4), lineWidth: 1))
    }

    private func filaDato(_ titulo: String, _ valor: String) -> some View {
        HStack {
            Text(titulo).foregroundStyle(.primary)
            Spacer()
            Text(valor).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}
