import SwiftUI
import BotikinKit

struct BotiquinView: View {
    @EnvironmentObject private var sesion: SessionStore
    @StateObject private var modelo = BotiquinViewModel()
    @State private var mostrandoFormulario = false
    @State private var mostrandoPerfil = false
    @State private var medicinaEnEdicion: Medicine?

    var body: some View {
        NavigationStack {
            Group {
                switch modelo.estado {
                case .inicial, .cargando:
                    ProgressView("Cargando botiquín…")
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
            .navigationTitle("Mi Botiquín")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { TokenPill() }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        mostrandoFormulario = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        mostrandoPerfil = true
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
            }
            .searchable(text: $modelo.busqueda, prompt: "Buscar remedio…")
            .refreshable { await modelo.cargar(token: sesion.accessToken) }
            .task {
                modelo.usuarioActual = sesion.session?.userID
                await modelo.cargar(token: sesion.accessToken)
            }
            .sheet(isPresented: $mostrandoFormulario) {
                MedicineFormView(modelo: modelo)
            }
            .sheet(isPresented: $mostrandoPerfil) {
                PerfilView()
            }
            .sheet(item: $medicinaEnEdicion) { medicina in
                MedicineFormView(modelo: modelo, medicina: medicina)
            }
            .alert("Error", isPresented: .init(
                get: { modelo.errorAccion != nil },
                set: { if !$0 { modelo.errorAccion = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(modelo.errorAccion ?? "")
            }
        }
    }

    private var contenido: some View {
        List {
            let resumen = modelo.resumenAlertas
            if resumen.vencidos > 0 || resumen.porVencer > 0 {
                Section {
                    AlertBanner(vencidos: resumen.vencidos, porVencer: resumen.porVencer)
                        .listRowBackground(Color.botikinPrimario)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ExpiryFilter.allCases, id: \.self) { filtro in
                            FilterChip(titulo: filtro.rawValue,
                                       activo: modelo.filtro == filtro) {
                                modelo.filtro = filtro
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            Section {
                if modelo.medicinasFiltradas.isEmpty {
                    EmptyState(icono: "pills",
                               titulo: "Nada por aquí",
                               mensaje: modelo.medicinas.isEmpty
                                   ? "Agrega tu primer remedio con el botón +"
                                   : "Ningún remedio calza con el filtro")
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(modelo.medicinasFiltradas) { medicina in
                        MedicineRow(medicina: medicina)
                            .contentShape(Rectangle())
                            .onTapGesture { medicinaEnEdicion = medicina }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task {
                                        await modelo.eliminar(medicina,
                                                              token: sesion.accessToken)
                                    }
                                } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

struct MedicineRow: View {
    let medicina: Medicine

    private var status: ExpiryStatus {
        ExpiryCalculator.status(para: medicina.fechaVencimiento)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(status.color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(medicina.nombre)
                    .font(.headline)
                HStack(spacing: 6) {
                    Image(systemName: "pills")
                        .foregroundStyle(.secondary)
                    Text("\(medicina.unidades) unidades")
                        .foregroundStyle(.secondary)
                    Image(systemName: "calendar")
                        .foregroundStyle(status.color)
                    Text(status.descripcion)
                        .foregroundStyle(status.color)
                }
                .font(.subheadline)
            }
            Spacer()
            StatusBadge(texto: status.etiqueta, color: status.color)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}
