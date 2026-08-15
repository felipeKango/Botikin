import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var sesion: SessionStore

    var body: some View {
        TabView {
            BotiquinView()
                .tabItem { Label("Botiquín", systemImage: "cross.case.fill") }
            RecetaView()
                .tabItem { Label("Receta", systemImage: "doc.viewfinder") }
            WhatsAppView()
                .tabItem { Label("WhatsApp", systemImage: "bubble.left.fill") }
            HistorialView()
                .tabItem { Label("Historial", systemImage: "clock.fill") }
            NavigationStack { TokensView() }
                .tabItem { Label("Tokens", systemImage: "bolt.fill") }
        }
        // Paywall global: aparece cuando el portero bloquea una acción
        .sheet(isPresented: $sesion.mostrarPaywall) {
            NavigationStack {
                SuscripcionView(mensajeBloqueo: sesion.mensajePaywall)
            }
        }
    }
}
