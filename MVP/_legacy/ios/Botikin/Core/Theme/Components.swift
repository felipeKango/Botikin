import SwiftUI
import BotikinKit

// MARK: - Token pill "⚡ 2k" (visible en toda la app)

struct TokenPill: View {
    @EnvironmentObject private var sesion: SessionStore

    var body: some View {
        NavigationLink {
            TokensView()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bolt.circle.fill")
                    .foregroundStyle(.white, Color.botikinVerde)
                Text(sesion.accountant?.saldoCompacto ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.botikinVerde)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.botikinVerde.opacity(0.15), in: Capsule())
        }
    }
}

// MARK: - Chips de filtro tipo píldora

struct FilterChip: View {
    let titulo: String
    let activo: Bool
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Text(titulo)
                .font(.subheadline.weight(activo ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(activo ? Color.botikinPrimario : Color(.systemGray5),
                            in: Capsule())
                .foregroundStyle(activo ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Badge de estado tipo píldora

struct StatusBadge: View {
    let texto: String
    let color: Color

    var body: some View {
        Text(texto)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Banner de alerta (dentro del header rojo del botiquín)

struct AlertBanner: View {
    let vencidos: Int
    let porVencer: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                if vencidos > 0 {
                    Text("\(vencidos) remedio(s) vencido(s)")
                        .font(.subheadline.weight(.semibold))
                }
                if porVencer > 0 {
                    Text("\(porVencer) vence(n) en menos de 7 días")
                        .font(.subheadline)
                }
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - Tarjeta de estadística (grid del historial)

struct StatCard: View {
    let icono: String
    let color: Color
    let valor: String
    let titulo: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icono)
                .font(.title3)
                .foregroundStyle(color)
            Text(valor)
                .font(.title2.bold())
            Text(titulo)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Botón primario

struct PrimaryButton: View {
    let titulo: String
    var cargando = false
    var deshabilitado = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            ZStack {
                Text(titulo).opacity(cargando ? 0 : 1)
                if cargando { ProgressView().tint(.white) }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.botikinPrimario.opacity(deshabilitado ? 0.4 : 1),
                        in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .disabled(cargando || deshabilitado)
    }
}

// MARK: - Estados de carga / error / vacío

struct ErrorBanner: View {
    let mensaje: String
    var reintentar: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                Text(mensaje).font(.subheadline)
            }
            .foregroundStyle(.secondary)
            if let reintentar {
                Button("Reintentar", action: reintentar)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.botikinPrimario)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }
}

struct EmptyState: View {
    let icono: String
    let titulo: String
    let mensaje: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icono)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(titulo).font(.headline)
            Text(mensaje)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Estado genérico de carga

enum Cargable<T> {
    case inicial
    case cargando
    case listo(T)
    case error(String)

    var valor: T? {
        if case .listo(let v) = self { return v }
        return nil
    }
}
