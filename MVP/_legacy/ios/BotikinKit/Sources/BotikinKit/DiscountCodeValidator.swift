import Foundation

/// Reglas de validación de códigos de descuento. La validación
/// autoritativa vive en el backend (redeem_discount_code); esta réplica
/// permite testear la regla de negocio y validar el formato en la app.
public struct DiscountCode: Equatable, Sendable {
    public var codigo: String
    public var mesesGratis: Int
    public var usosMaximos: Int
    public var usosActuales: Int
    public var activo: Bool
    public var expiraEl: Date?

    public init(codigo: String, mesesGratis: Int = 1, usosMaximos: Int = 100,
                usosActuales: Int = 0, activo: Bool = true, expiraEl: Date? = nil) {
        self.codigo = codigo
        self.mesesGratis = mesesGratis
        self.usosMaximos = usosMaximos
        self.usosActuales = usosActuales
        self.activo = activo
        self.expiraEl = expiraEl
    }
}

public enum DiscountCodeError: Error, Equatable {
    case formatoInvalido
    case noExiste
    case inactivo
    case expirado
    case agotado
    case yaUsado

    public var mensaje: String {
        switch self {
        case .formatoInvalido: "Ingresa un código válido (letras y números)"
        case .noExiste: "El código no existe"
        case .inactivo: "El código ya no está activo"
        case .expirado: "El código expiró"
        case .agotado: "El código agotó sus usos"
        case .yaUsado: "Ya usaste este código"
        }
    }
}

public enum DiscountCodeValidator {

    /// Normaliza el input del usuario: trim + mayúsculas.
    public static func normalizar(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Chequeo de formato local antes de consultar el backend:
    /// 4–20 caracteres alfanuméricos.
    public static func formatoValido(_ input: String) -> Bool {
        let code = normalizar(input)
        guard (4...20).contains(code.count) else { return false }
        return code.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Valida un código contra sus reglas de negocio.
    /// `codigoYaUsadoPorUsuario` = el código que el usuario canjeó antes.
    public static func validar(
        _ code: DiscountCode,
        hoy: Date = .now,
        codigoYaUsadoPorUsuario: String? = nil
    ) -> Result<DiscountCode, DiscountCodeError> {
        guard code.activo else { return .failure(.inactivo) }
        if let expira = code.expiraEl,
           Calendar.current.startOfDay(for: expira) < Calendar.current.startOfDay(for: hoy) {
            return .failure(.expirado)
        }
        guard code.usosActuales < code.usosMaximos else { return .failure(.agotado) }
        if let usado = codigoYaUsadoPorUsuario,
           normalizar(usado) == normalizar(code.codigo) {
            return .failure(.yaUsado)
        }
        return .success(code)
    }
}
