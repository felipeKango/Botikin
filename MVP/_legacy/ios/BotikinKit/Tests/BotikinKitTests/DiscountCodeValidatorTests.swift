import XCTest
@testable import BotikinKit

final class DiscountCodeValidatorTests: XCTestCase {

    private let hoy = ISO8601DateFormatter().date(from: "2026-07-04T12:00:00Z")!

    // MARK: Formato local

    func testNormalizarTrimYMayusculas() {
        XCTAssertEqual(DiscountCodeValidator.normalizar("  kango2026 \n"), "KANGO2026")
    }

    func testFormatoValido() {
        XCTAssertTrue(DiscountCodeValidator.formatoValido("KANGO2026"))
        XCTAssertTrue(DiscountCodeValidator.formatoValido("abc1"))
        XCTAssertFalse(DiscountCodeValidator.formatoValido("ab"), "muy corto")
        XCTAssertFalse(DiscountCodeValidator.formatoValido("CON ESPACIO"))
        XCTAssertFalse(DiscountCodeValidator.formatoValido("GUION-MEDIO"))
        XCTAssertFalse(DiscountCodeValidator.formatoValido(String(repeating: "A", count: 21)))
    }

    // MARK: Reglas de negocio

    func testCodigoValidoPasa() {
        let code = DiscountCode(codigo: "KANGO2026", mesesGratis: 1,
                                usosMaximos: 500, usosActuales: 10)
        let result = DiscountCodeValidator.validar(code, hoy: hoy)
        XCTAssertEqual(result, .success(code))
    }

    func testCodigoInactivoFalla() {
        let code = DiscountCode(codigo: "INACTIVO", activo: false)
        XCTAssertEqual(DiscountCodeValidator.validar(code, hoy: hoy),
                       .failure(.inactivo))
    }

    func testCodigoExpiradoFalla() {
        let ayer = Calendar.current.date(byAdding: .day, value: -1, to: hoy)!
        let code = DiscountCode(codigo: "VIEJO", expiraEl: ayer)
        XCTAssertEqual(DiscountCodeValidator.validar(code, hoy: hoy),
                       .failure(.expirado))
    }

    func testCodigoQueExpiraHoyTodaviaVale() {
        let code = DiscountCode(codigo: "ULTIMODIA", expiraEl: hoy)
        XCTAssertEqual(DiscountCodeValidator.validar(code, hoy: hoy), .success(code))
    }

    func testCodigoAgotadoFalla() {
        let code = DiscountCode(codigo: "AGOTADO", usosMaximos: 1, usosActuales: 1)
        XCTAssertEqual(DiscountCodeValidator.validar(code, hoy: hoy),
                       .failure(.agotado))
    }

    func testCodigoYaUsadoPorElUsuarioFalla() {
        let code = DiscountCode(codigo: "KANGO2026")
        let result = DiscountCodeValidator.validar(
            code, hoy: hoy, codigoYaUsadoPorUsuario: "kango2026")
        XCTAssertEqual(result, .failure(.yaUsado))
    }

    func testMensajesDeErrorEnEspanol() {
        XCTAssertEqual(DiscountCodeError.agotado.mensaje, "El código agotó sus usos")
        XCTAssertEqual(DiscountCodeError.yaUsado.mensaje, "Ya usaste este código")
    }
}
