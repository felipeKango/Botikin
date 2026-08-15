import Foundation
import UserNotifications
import UIKit
import BotikinKit

/// Alertas del módulo 8: push APNs (vía notif-api) y notificaciones
/// locales de respaldo por vencimientos.
@MainActor
final class NotificationsManager: NSObject {
    static let shared = NotificationsManager()

    private weak var sesion: SessionStore?

    func configurar(sesion: SessionStore) {
        self.sesion = sesion
        Task {
            let centro = UNUserNotificationCenter.current()
            let permiso = try? await centro.requestAuthorization(
                options: [.alert, .badge, .sound])
            guard permiso == true else { return }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// AppDelegate entrega aquí el device token de APNs; se registra en
    /// el backend para que expiry-scheduler pueda enviar push.
    func registrarDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard let sesion, let accessToken = sesion.accessToken else { return }
        Task {
            struct Respuesta: Decodable { let ok: Bool }
            _ = try? await APIClient.shared.invoke(
                "notif-api",
                body: ["action": "register_device", "device_token": token],
                accessToken: accessToken) as Respuesta
        }
    }

    /// Notificaciones locales de respaldo: programa un aviso a las 09:00
    /// del día que el remedio entra en ventana de "vence pronto".
    func programarAlertasLocales(medicinas: [Medicine]) {
        let centro = UNUserNotificationCenter.current()
        centro.removePendingNotificationRequests(
            withIdentifiers: medicinas.map { "vence-\($0.id.uuidString)" })

        let cal = Calendar.current
        for medicina in medicinas {
            let status = ExpiryCalculator.status(para: medicina.fechaVencimiento)
            guard case .venceEsteMes = status else { continue }

            guard let diaAviso = cal.date(byAdding: .day, value: -7,
                                          to: medicina.fechaVencimiento) else { continue }
            var componentes = cal.dateComponents([.year, .month, .day], from: diaAviso)
            componentes.hour = 9

            let contenido = UNMutableNotificationContent()
            contenido.title = "Botikin — vencimiento cercano"
            contenido.body = "Tu \(medicina.nombre) \(medicina.dosis) vence en 7 días. Úsalo pronto."
            contenido.sound = .default

            let request = UNNotificationRequest(
                identifier: "vence-\(medicina.id.uuidString)",
                content: contenido,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: componentes, repeats: false))
            centro.add(request)
        }
    }
}

/// AppDelegate: recibe el device token de APNs.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            NotificationsManager.shared.registrarDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Simulador o permisos denegados: la app sigue con alertas locales.
    }
}
