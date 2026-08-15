import SwiftUI
import BotikinKit

// MARK: - Paleta Botikin

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    /// Rojo coral: headers, botones primarios, tab activo.
    static let botikinPrimario = Color(hex: 0xE8503A)
    /// Verde: vigente / entregado / éxito.
    static let botikinVerde = Color(hex: 0x34C759)
    /// Naranjo: vence pronto / tokens / comprar.
    static let botikinNaranjo = Color(hex: 0xFF9500)
    /// Rojo semántico: vencido.
    static let botikinRojo = Color(hex: 0xFF3B30)
    /// Azul: enviado.
    static let botikinAzul = Color(hex: 0x007AFF)
    /// Morado: recetas / análisis AI.
    static let botikinMorado = Color(hex: 0xAF52DE)
}

// MARK: - Semántica de estados

extension ExpiryStatus {
    var color: Color {
        switch self {
        case .vencido: .botikinRojo
        case .vencePronto: .botikinNaranjo
        case .venceEsteMes, .vigente: .botikinVerde
        }
    }
}

extension DeliveryStatus {
    var color: Color {
        switch self {
        case .sent: .botikinAzul
        case .delivered: .botikinVerde
        case .failed: .botikinRojo
        }
    }
}

// MARK: - Formato de fechas y números (español de Chile)

enum Formato {
    static let localeChile = Locale(identifier: "es_CL")

    static func fechaCorta(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = localeChile
        f.dateFormat = "d MMM · HH:mm"
        return f.string(from: date)
    }

    static func fechaLarga(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = localeChile
        f.dateStyle = .long
        return f.string(from: date)
    }

    /// "2.400" con separador de miles chileno.
    static func miles(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = localeChile
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// "$4.990" CLP.
    static func clp(_ n: Int) -> String { "$\(miles(n))" }
}
