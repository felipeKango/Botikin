import Foundation
import BotikinKit

struct UsoDiario: Identifiable, Equatable {
    let dia: Date
    let tokens: Int
    var id: Date { dia }
}

@MainActor
final class TokensViewModel: ObservableObject {
    @Published var usoUltimos7Dias: [UsoDiario] = []
    @Published var cargandoUso = false

    private let api = APIClient.shared

    func cargarUso(token: String?) async {
        guard let token else { return }
        cargandoUso = usoUltimos7Dias.isEmpty
        defer { cargandoUso = false }

        let cal = Calendar.current
        let desde = cal.date(byAdding: .day, value: -6,
                             to: cal.startOfDay(for: .now))!
        do {
            let usos: [TokenUsageEntry] = try await api.select(
                "token_usage",
                query: [
                    URLQueryItem(name: "select",
                                 value: "id,tipo_accion,tokens_consumidos,created_at"),
                    URLQueryItem(name: "created_at",
                                 value: "gte.\(ISO8601DateFormatter().string(from: desde))"),
                    URLQueryItem(name: "order", value: "created_at.asc"),
                ],
                accessToken: token)

            let porDia = Dictionary(grouping: usos) {
                cal.startOfDay(for: $0.createdAt)
            }
            usoUltimos7Dias = (0..<7).map { offset in
                let dia = cal.date(byAdding: .day, value: offset, to: desde)!
                let total = porDia[dia]?.reduce(0) { $0 + $1.tokensConsumidos } ?? 0
                return UsoDiario(dia: dia, tokens: total)
            }
        } catch {
            // El gráfico es secundario: si falla, se muestra vacío.
        }
    }
}
