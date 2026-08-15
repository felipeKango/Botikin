import Foundation

/// Configuración del backend. Los valores viven en Secrets.plist
/// (NO versionado; ver Secrets.example.plist y README).
/// Aquí solo van la URL del proyecto y el anon key público —
/// las API keys de Anthropic/Twilio/Transbank JAMÁS tocan la app.
enum AppConfig {
    private static let secrets: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil) as? [String: Any]
        else {
            fatalError("Falta Secrets.plist: copia Secrets.example.plist y completa tus valores")
        }
        return plist
    }()

    static var supabaseURL: URL {
        guard let raw = secrets["SUPABASE_URL"] as? String, let url = URL(string: raw) else {
            fatalError("SUPABASE_URL inválida en Secrets.plist")
        }
        return url
    }

    static var supabaseAnonKey: String {
        guard let key = secrets["SUPABASE_ANON_KEY"] as? String, !key.isEmpty else {
            fatalError("SUPABASE_ANON_KEY vacía en Secrets.plist")
        }
        return key
    }

    static var functionsURL: URL { supabaseURL.appendingPathComponent("functions/v1") }
    static var restURL: URL { supabaseURL.appendingPathComponent("rest/v1") }
    static var storageURL: URL { supabaseURL.appendingPathComponent("storage/v1") }
}
