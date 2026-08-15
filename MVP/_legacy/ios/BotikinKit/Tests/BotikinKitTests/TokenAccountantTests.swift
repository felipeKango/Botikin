import XCTest
@testable import BotikinKit

final class TokenAccountantTests: XCTestCase {

    private func sub(plan: Plan, total: Int, usados: Int,
                     estado: String = "active") -> Subscription {
        Subscription(plan: plan, estado: estado, tokensTotal: total,
                     tokensUsados: usados,
                     fechaRenovacion: .now.addingTimeInterval(15 * 86_400))
    }

    // MARK: Descuento

    func testConsumirDescuentaElCostoDeLaAccion() throws {
        var acc = TokenAccountant(subscription: sub(plan: .basic, total: 5_000, usados: 0))
        try acc.consumir(.prescriptionAnalysis) // 1.000
        XCTAssertEqual(acc.saldo, 4_000)
        try acc.consumir(.cabinetAnalysis) // 400
        XCTAssertEqual(acc.saldo, 3_600)
    }

    func testConsumirConSaldoExactoDejaEnCero() throws {
        var acc = TokenAccountant(subscription: sub(plan: .free, total: 500, usados: 100))
        try acc.consumir(.cabinetAnalysis) // 400, saldo exacto
        XCTAssertEqual(acc.saldo, 0)
    }

    // MARK: El portero: bloqueo sin tokens

    func testConsumirSinSaldoLanzaYNoDescuenta() {
        var acc = TokenAccountant(subscription: sub(plan: .free, total: 500, usados: 300))
        XCTAssertFalse(acc.puedeEjecutar(.prescriptionAnalysis))
        XCTAssertThrowsError(try acc.consumir(.prescriptionAnalysis)) { error in
            XCTAssertEqual(error as? TokenAccountant.GateError,
                           .saldoInsuficiente(faltan: 800))
        }
        XCTAssertEqual(acc.saldo, 200, "un intento bloqueado no descuenta nada")
    }

    func testSuscripcionInactivaBloqueaTodo() {
        var acc = TokenAccountant(
            subscription: sub(plan: .basic, total: 5_000, usados: 0, estado: "canceled"))
        XCTAssertThrowsError(try acc.consumir(.assistantChat)) { error in
            XCTAssertEqual(error as? TokenAccountant.GateError, .suscripcionInactiva)
        }
    }

    // MARK: Plan Pro ilimitado

    func testPlanProIlimitadoNuncaBloquea() throws {
        var acc = TokenAccountant(subscription: sub(plan: .pro, total: -1, usados: 0))
        XCTAssertTrue(acc.esIlimitado)
        XCTAssertEqual(acc.saldo, -1)
        for _ in 0..<100 {
            XCTAssertTrue(acc.puedeEjecutar(.prescriptionAnalysis))
            try acc.consumir(.prescriptionAnalysis)
        }
        XCTAssertEqual(acc.saldo, -1)
    }

    // MARK: Sincronización con el backend

    func testSincronizarActualizaUsadosSegunRestantes() {
        var acc = TokenAccountant(subscription: sub(plan: .basic, total: 5_000, usados: 0))
        acc.sincronizar(tokensRestantes: 2_400)
        XCTAssertEqual(acc.saldo, 2_400)
        XCTAssertEqual(acc.subscription.tokensUsados, 2_600)
    }

    // MARK: Presentación

    func testSaldoCompactoParaElPill() {
        XCTAssertEqual(
            TokenAccountant(subscription: sub(plan: .basic, total: 5_000, usados: 3_000))
                .saldoCompacto, "2k")
        XCTAssertEqual(
            TokenAccountant(subscription: sub(plan: .basic, total: 5_000, usados: 2_600))
                .saldoCompacto, "2.4k")
        XCTAssertEqual(
            TokenAccountant(subscription: sub(plan: .free, total: 500, usados: 0))
                .saldoCompacto, "500")
        XCTAssertEqual(
            TokenAccountant(subscription: sub(plan: .pro, total: -1, usados: 0))
                .saldoCompacto, "∞")
    }

    func testFraccionConsumidaParaBarraDeProgreso() {
        let acc = TokenAccountant(subscription: sub(plan: .basic, total: 5_000, usados: 2_600))
        XCTAssertEqual(acc.fraccionConsumida, 0.52, accuracy: 0.001)
        let pro = TokenAccountant(subscription: sub(plan: .pro, total: -1, usados: 0))
        XCTAssertEqual(pro.fraccionConsumida, 0)
    }
}
