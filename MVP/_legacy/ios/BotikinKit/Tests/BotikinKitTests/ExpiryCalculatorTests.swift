import XCTest
@testable import BotikinKit

final class ExpiryCalculatorTests: XCTestCase {

    private let hoy = ISO8601DateFormatter().date(from: "2026-07-04T12:00:00Z")!

    private func fecha(dias: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: dias, to: hoy)!
    }

    // MARK: Estados

    func testVencidoHaceDias() {
        let st = ExpiryCalculator.status(para: fecha(dias: -3), desde: hoy)
        XCTAssertEqual(st, .vencido(hace: 3))
        XCTAssertEqual(st.etiqueta, "Vencido")
        XCTAssertEqual(st.descripcion, "Venció hace 3d")
        XCTAssertTrue(st.esUrgente)
    }

    func testVenceHoyCuentaComoVencido() {
        let st = ExpiryCalculator.status(para: fecha(dias: 0), desde: hoy)
        XCTAssertEqual(st, .vencido(hace: 0))
        XCTAssertEqual(st.descripcion, "Venció hoy")
    }

    func testVenceProntoDentroDe7Dias() {
        XCTAssertEqual(ExpiryCalculator.status(para: fecha(dias: 1), desde: hoy),
                       .vencePronto(en: 1))
        let st = ExpiryCalculator.status(para: fecha(dias: 7), desde: hoy)
        XCTAssertEqual(st, .vencePronto(en: 7))
        XCTAssertEqual(st.etiqueta, "Vence pronto")
        XCTAssertEqual(st.descripcion, "Vence en 7d")
        XCTAssertTrue(st.esUrgente)
    }

    func testVenceEsteMesEntre8y30Dias() {
        let st = ExpiryCalculator.status(para: fecha(dias: 15), desde: hoy)
        XCTAssertEqual(st, .venceEsteMes(en: 15))
        XCTAssertEqual(st.etiqueta, "Vigente")
        XCTAssertFalse(st.esUrgente)
    }

    func testVigenteMasDe30Dias() {
        let st = ExpiryCalculator.status(para: fecha(dias: 122), desde: hoy)
        XCTAssertEqual(st, .vigente(en: 122))
        XCTAssertEqual(st.etiqueta, "Vigente")
        XCTAssertEqual(st.descripcion, "Vence en 122d")
    }

    func testDiasParaVencerIgnoraLaHora() {
        // Vence "mañana a las 08:00" visto desde hoy a las 23:00 → 1 día
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "America/Santiago")!
        let tarde = cal.date(bySettingHour: 23, minute: 0, second: 0, of: hoy)!
        let mananaTemprano = cal.date(
            bySettingHour: 8, minute: 0, second: 0, of: fecha(dias: 1))!
        XCTAssertEqual(
            ExpiryCalculator.diasParaVencer(mananaTemprano, desde: tarde, calendar: cal), 1)
    }

    // MARK: Filtros del botiquín

    private var botiquin: [Medicine] {
        [
            Medicine(nombre: "Amoxicilina 500mg", fechaVencimiento: fecha(dias: -3)),
            Medicine(nombre: "Omeprazol 20mg", fechaVencimiento: fecha(dias: 2)),
            Medicine(nombre: "Ibuprofeno 400mg", fechaVencimiento: fecha(dias: 4)),
            Medicine(nombre: "Loratadina 10mg", fechaVencimiento: fecha(dias: 20)),
            Medicine(nombre: "Paracetamol 500mg", fechaVencimiento: fecha(dias: 122)),
        ]
    }

    func testFiltroVencidos() {
        let r = ExpiryCalculator.filtrar(botiquin, por: .vencidos, desde: hoy)
        XCTAssertEqual(r.map(\.nombre), ["Amoxicilina 500mg"])
    }

    func testFiltroUrgenteIncluyeVencidosYPorVencer() {
        let r = ExpiryCalculator.filtrar(botiquin, por: .urgente, desde: hoy)
        XCTAssertEqual(r.count, 3)
    }

    func testFiltroEsteMes() {
        let r = ExpiryCalculator.filtrar(botiquin, por: .esteMes, desde: hoy)
        XCTAssertEqual(r.map(\.nombre), ["Loratadina 10mg"])
    }

    func testFiltroVigentes() {
        let r = ExpiryCalculator.filtrar(botiquin, por: .vigentes, desde: hoy)
        XCTAssertEqual(r.count, 2)
    }

    func testFiltroTodosNoFiltra() {
        XCTAssertEqual(ExpiryCalculator.filtrar(botiquin, por: .todos, desde: hoy).count, 5)
    }

    // MARK: Banner de alertas

    func testResumenAlertasParaElBanner() {
        let (vencidos, porVencer) = ExpiryCalculator.resumenAlertas(botiquin, desde: hoy)
        XCTAssertEqual(vencidos, 1)
        XCTAssertEqual(porVencer, 2)
    }
}
