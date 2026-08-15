import SwiftUI

@main
struct BotikinApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var sesion = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sesion)
                .tint(.botikinPrimario)
                .onOpenURL { url in
                    // Retorno del checkout WebPay: botikin://payment-result?status=ok
                    guard url.host == "payment-result" || url.path.contains("payment-result"),
                          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          let status = components.queryItems?
                              .first(where: { $0.name == "status" })?.value
                    else { return }
                    NotificationCenter.default.post(
                        name: .webpayResultado, object: nil,
                        userInfo: ["status": status])
                    if status == "ok" {
                        Task { await sesion.refrescarSuscripcion() }
                    }
                }
                .task(id: sesion.estaAutenticado) {
                    if sesion.estaAutenticado {
                        await sesion.refrescarSuscripcion()
                        NotificationsManager.shared.configurar(sesion: sesion)
                    }
                }
        }
    }
}

extension Notification.Name {
    static let webpayResultado = Notification.Name("webpayResultado")
}

struct RootView: View {
    @EnvironmentObject private var sesion: SessionStore

    var body: some View {
        if sesion.estaAutenticado {
            MainTabView()
        } else {
            LoginView()
        }
    }
}
