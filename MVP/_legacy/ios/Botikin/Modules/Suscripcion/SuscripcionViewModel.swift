import Foundation
import BotikinKit

@MainActor
final class SuscripcionViewModel: ObservableObject {

    enum EstadoCheckout: Equatable {
        case inicial
        case validandoCodigo
        case codigoValido(mesesGratis: Int)
        case codigoInvalido(String)
        case iniciandoPago
        case esperandoWebPay
        case exito(String)
        case fallo(String)
    }

    @Published var planSeleccionado: Plan = .basic
    @Published var codigoDescuento = ""
    @Published var estado: EstadoCheckout = .inicial
    @Published var urlWebPay: URL?
    /// Distinto de nil cuando discount-code-api aprobó el código.
    @Published private(set) var mesesGratisValidados: Int?

    private let api = APIClient.shared

    var codigoNormalizado: String {
        DiscountCodeValidator.normalizar(codigoDescuento)
    }

    /// Valida el código contra discount-code-api (la tabla es invisible
    /// para el cliente por RLS).
    func validarCodigo(sesion: SessionStore) async {
        guard DiscountCodeValidator.formatoValido(codigoDescuento) else {
            estado = .codigoInvalido(DiscountCodeError.formatoInvalido.mensaje)
            return
        }
        estado = .validandoCodigo
        mesesGratisValidados = nil
        struct Respuesta: Decodable {
            let valido: Bool
            let motivo: String?
            let meses_gratis: Int?
        }
        do {
            let r: Respuesta = try await api.invoke(
                "discount-code-api",
                body: ["action": "validate", "codigo": codigoNormalizado],
                accessToken: sesion.accessToken)
            if r.valido {
                mesesGratisValidados = r.meses_gratis ?? 1
                estado = .codigoValido(mesesGratis: r.meses_gratis ?? 1)
            } else {
                estado = .codigoInvalido(r.motivo ?? "Código inválido")
            }
        } catch {
            estado = .codigoInvalido(error.localizedDescription)
        }
    }

    /// Inicia el checkout. Con código válido el backend activa el plan
    /// directo (mes gratis); si no, devuelve la URL de WebPay.
    func suscribirse(sesion: SessionStore) async {
        estado = .iniciandoPago
        struct Respuesta: Decodable {
            let estado: String?
            let meses_gratis: Int?
            let url: String?
            let token: String?
        }
        var body: [String: Any] = [
            "action": "create_transaction",
            "plan": planSeleccionado.rawValue,
        ]
        if mesesGratisValidados != nil, !codigoNormalizado.isEmpty {
            body["codigo_descuento"] = codigoNormalizado
        }
        do {
            let r: Respuesta = try await api.invoke(
                "payments-api", body: body, accessToken: sesion.accessToken)

            if r.estado == "activated_with_code" {
                await sesion.refrescarSuscripcion()
                estado = .exito("¡Listo! Activamos tu plan \(planSeleccionado.nombre) con \(r.meses_gratis ?? 1) mes(es) gratis 🎉")
            } else if let urlString = r.url, let token = r.token,
                      let url = URL(string: "\(urlString)?token_ws=\(token)") {
                urlWebPay = url
                estado = .esperandoWebPay
            } else {
                estado = .fallo("El servidor no entregó la URL de pago")
            }
        } catch {
            estado = .fallo(error.localizedDescription)
        }
    }

    /// Resultado del deep link botikin://payment-result?status=…
    func procesarResultadoWebPay(_ status: String, sesion: SessionStore) async {
        urlWebPay = nil
        switch status {
        case "ok":
            await sesion.refrescarSuscripcion()
            estado = .exito("¡Pago aprobado! Tu plan \(planSeleccionado.nombre) ya está activo 🎉")
        case "aborted":
            estado = .fallo("Cancelaste el pago. Puedes intentarlo cuando quieras.")
        default:
            estado = .fallo("El pago no fue aprobado. Revisa tu tarjeta e intenta de nuevo.")
        }
    }
}
