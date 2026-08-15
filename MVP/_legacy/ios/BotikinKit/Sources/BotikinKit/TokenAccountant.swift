import Foundation

/// Lógica local del "portero" de tokens. El descuento real y autoritativo
/// ocurre en el backend (RPC consume_tokens); esta réplica local permite
/// mostrar saldos, bloquear acciones sin red y testear la regla de negocio.
public struct TokenAccountant: Sendable {

    public enum GateError: Error, Equatable {
        case saldoInsuficiente(faltan: Int)
        case suscripcionInactiva
    }

    public private(set) var subscription: Subscription

    public init(subscription: Subscription) {
        self.subscription = subscription
    }

    /// Tokens disponibles. -1 = ilimitado (plan Pro).
    public var saldo: Int {
        guard subscription.tokensTotal != -1 else { return -1 }
        return max(0, subscription.tokensTotal - subscription.tokensUsados)
    }

    public var esIlimitado: Bool { subscription.tokensTotal == -1 }

    /// Fracción consumida del ciclo [0, 1] para la barra de progreso.
    public var fraccionConsumida: Double {
        guard !esIlimitado, subscription.tokensTotal > 0 else { return 0 }
        return min(1, Double(subscription.tokensUsados) / Double(subscription.tokensTotal))
    }

    public func diasParaRenovacion(desde ahora: Date = .now) -> Int {
        let segundos = subscription.fechaRenovacion.timeIntervalSince(ahora)
        return max(0, Int(ceil(segundos / 86_400)))
    }

    /// ¿Alcanza el saldo para esta acción?
    public func puedeEjecutar(_ accion: TokenAction) -> Bool {
        esIlimitado || saldo >= accion.costo
    }

    /// Descuenta el costo de la acción. Lanza si no alcanza el saldo
    /// (el mismo bloqueo que aplica el backend con 402 + upgrade).
    @discardableResult
    public mutating func consumir(_ accion: TokenAction) throws -> Int {
        guard subscription.estado == "active" else {
            throw GateError.suscripcionInactiva
        }
        if esIlimitado {
            return -1
        }
        guard saldo >= accion.costo else {
            throw GateError.saldoInsuficiente(faltan: accion.costo - saldo)
        }
        subscription.tokensUsados += accion.costo
        return saldo
    }

    /// Sincroniza con el saldo reportado por el backend tras cada acción.
    public mutating func sincronizar(tokensRestantes: Int) {
        if tokensRestantes == -1 {
            subscription.tokensTotal = -1
        } else if subscription.tokensTotal != -1 {
            subscription.tokensUsados = max(0, subscription.tokensTotal - tokensRestantes)
        }
    }

    /// Formato compacto para el pill del token meter: "⚡ 2k", "500", "∞".
    public var saldoCompacto: String {
        if esIlimitado { return "∞" }
        let s = saldo
        if s >= 1_000 {
            let miles = Double(s) / 1_000
            return miles == miles.rounded()
                ? "\(Int(miles))k"
                : String(format: "%.1fk", miles)
        }
        return "\(s)"
    }
}
