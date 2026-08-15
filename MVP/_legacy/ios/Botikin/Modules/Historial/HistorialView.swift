import SwiftUI
import BotikinKit

struct HistorialView: View {
    @EnvironmentObject private var sesion: SessionStore
    @StateObject private var modelo = HistorialViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch modelo.estado {
                case .inicial, .cargando:
                    ProgressView("Cargando historial…")
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
            .navigationTitle("Mi Historial")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { TokenPill() }
            }
            .refreshable { await modelo.cargar(token: sesion.accessToken) }
            .task { await modelo.cargar(token: sesion.accessToken) }
        }
    }

    private var contenido: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                resumenSalud
                filtros
                timeline
            }
            .padding(.horizontal)
        }
    }

    // MARK: Resumen de salud (grid 2×3)

    private var resumenSalud: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resumen de salud")
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: 3), spacing: 10) {
                StatCard(icono: "pills.fill", color: .botikinAzul,
                         valor: "\(modelo.resumen.remediosActivos)",
                         titulo: "Remedios activos")
                StatCard(icono: "doc.viewfinder", color: .botikinMorado,
                         valor: "\(modelo.resumen.recetasEscaneadas)",
                         titulo: "Recetas escaneadas")
                StatCard(icono: "brain.head.profile", color: .botikinMorado,
                         valor: "\(modelo.resumen.analisisAI)",
                         titulo: "Análisis AI")
                StatCard(icono: "calendar", color: .botikinAzul,
                         valor: "\(modelo.resumen.eventosDelMes)",
                         titulo: "Eventos este mes")
                StatCard(icono: "exclamationmark.triangle.fill", color: .botikinRojo,
                         valor: "\(modelo.resumen.vencidos)",
                         titulo: "Vencidos")
                StatCard(icono: "bolt.fill", color: .botikinNaranjo,
                         valor: Formato.miles(modelo.resumen.tokensUsados),
                         titulo: "Tokens usados")
            }
        }
        .padding()
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color(.systemGray5), lineWidth: 1))
    }

    // MARK: Filtros

    private var filtros: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PeriodoHistorial.allCases, id: \.self) { periodo in
                        FilterChip(titulo: periodo.rawValue,
                                   activo: modelo.periodo == periodo) {
                            modelo.periodo = periodo
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(titulo: "Todos", activo: modelo.filtroTipo == nil) {
                        modelo.filtroTipo = nil
                    }
                    ForEach(HistorialEvento.Tipo.allCases, id: \.self) { tipo in
                        FilterChip(titulo: tipo.rawValue,
                                   activo: modelo.filtroTipo == tipo) {
                            modelo.filtroTipo = tipo
                        }
                    }
                }
            }
        }
    }

    // MARK: Timeline agrupado por día

    private var timeline: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
            if modelo.eventosFiltrados.isEmpty {
                EmptyState(icono: "clock",
                           titulo: "Sin eventos",
                           mensaje: "Los análisis, recetas y mensajes aparecerán aquí")
            }
            ForEach(modelo.eventosPorDia, id: \.titulo) { grupo in
                Section {
                    ForEach(grupo.eventos) { evento in
                        HistorialEventoRow(evento: evento)
                        if evento != grupo.eventos.last { Divider() }
                    }
                } header: {
                    Text(grupo.titulo)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.vertical, 6)
                }
            }
        }
    }
}

struct HistorialEventoRow: View {
    let evento: HistorialEvento

    private var icono: (nombre: String, color: Color) {
        switch evento.tipo {
        case .recetaEscaneada: ("doc.viewfinder", .botikinMorado)
        case .analisisAI: ("brain.head.profile", .botikinMorado)
        case .whatsappEnviado: ("bubble.left.fill", .botikinVerde)
        case .remedioAgregado: ("pills.fill", .botikinAzul)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icono.nombre)
                .foregroundStyle(icono.color)
                .frame(width: 38, height: 38)
                .background(icono.color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(evento.titulo)
                    .font(.headline)
                Text(evento.detalle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    StatusBadge(texto: evento.tipo.rawValue, color: icono.color)
                    if let tokens = evento.tokens {
                        Text("\(Formato.miles(tokens)) tokens")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(evento.fecha.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }
}
