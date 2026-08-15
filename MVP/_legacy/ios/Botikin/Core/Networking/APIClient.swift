import Foundation

// MARK: - Errores

enum APIError: LocalizedError {
    case sinConexion
    case sesionExpirada
    case sinTokens(mensaje: String)          // 402: el portero bloqueó → upgrade
    case planRequerido(mensaje: String)      // 402: función no incluida en el plan
    case servidor(codigo: String, mensaje: String)
    case decodificacion

    var errorDescription: String? {
        switch self {
        case .sinConexion: "Sin conexión a internet. Revisa tu red e intenta de nuevo."
        case .sesionExpirada: "Tu sesión expiró. Inicia sesión nuevamente."
        case .sinTokens(let m), .planRequerido(let m): m
        case .servidor(_, let m): m
        case .decodificacion: "No pudimos leer la respuesta del servidor."
        }
    }

    var invitaUpgrade: Bool {
        switch self {
        case .sinTokens, .planRequerido: true
        default: false
        }
    }
}

private struct ErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let code: String
        let message: String
        let upgrade: Bool?
    }
    let error: Detail
}

// MARK: - Cliente

/// Cliente HTTP hacia Supabase: Edge Functions, PostgREST y Storage.
/// Sin SDKs: URLSession directo, async/await.
struct APIClient {
    static let shared = APIClient()

    /// El token de sesión lo provee SessionStore (se inyecta al llamar).
    private let session = URLSession.shared

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = Self.isoFractional.date(from: raw) { return date }
            if let date = Self.iso.date(from: raw) { return date }
            if let date = Self.dateOnly.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "Fecha inválida: \(raw)"))
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(Self.dateOnly.string(from: date))
        }
        return e
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()
    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Santiago")
        return f
    }()

    // MARK: Edge Functions

    func invoke<T: Decodable>(
        _ function: String,
        body: [String: Any],
        accessToken: String?
    ) async throws -> T {
        var request = URLRequest(url: AppConfig.functionsURL.appendingPathComponent(function))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await run(request)
    }

    // MARK: PostgREST

    func select<T: Decodable>(
        _ table: String,
        query: [URLQueryItem] = [],
        accessToken: String
    ) async throws -> T {
        var components = URLComponents(
            url: AppConfig.restURL.appendingPathComponent(table),
            resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        addRESTHeaders(&request, accessToken: accessToken)
        return try await run(request)
    }

    func insert<T: Decodable, Body: Encodable>(
        _ table: String,
        body: Body,
        accessToken: String
    ) async throws -> T {
        var request = URLRequest(url: AppConfig.restURL.appendingPathComponent(table))
        request.httpMethod = "POST"
        addRESTHeaders(&request, accessToken: accessToken)
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try Self.encoder.encode(body)
        return try await run(request)
    }

    func update<Body: Encodable>(
        _ table: String,
        id: UUID,
        body: Body,
        accessToken: String
    ) async throws {
        var components = URLComponents(
            url: AppConfig.restURL.appendingPathComponent(table),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        addRESTHeaders(&request, accessToken: accessToken)
        request.httpBody = try Self.encoder.encode(body)
        _ = try await runRaw(request)
    }

    func delete(_ table: String, id: UUID, accessToken: String) async throws {
        var components = URLComponents(
            url: AppConfig.restURL.appendingPathComponent(table),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        addRESTHeaders(&request, accessToken: accessToken)
        _ = try await runRaw(request)
    }

    // MARK: Storage

    /// Sube un archivo al bucket. Devuelve el path guardado.
    func uploadStorage(
        bucket: String,
        path: String,
        data: Data,
        contentType: String,
        accessToken: String
    ) async throws -> String {
        let url = AppConfig.storageURL
            .appendingPathComponent("object")
            .appendingPathComponent(bucket)
            .appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        _ = try await runRaw(request)
        return path
    }

    // MARK: Internos

    private func addRESTHeaders(_ request: inout URLRequest, accessToken: String) {
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func run<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await runRaw(request)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodificacion
        }
    }

    private func runRaw(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.sinConexion
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.sinConexion }

        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw APIError.sesionExpirada
        case 402:
            let env = try? Self.decoder.decode(ErrorEnvelope.self, from: data)
            let mensaje = env?.error.message ?? "Necesitas mejorar tu plan para esta acción."
            if env?.error.code == "plan_required" || env?.error.code == "plan_limit" {
                throw APIError.planRequerido(mensaje: mensaje)
            }
            throw APIError.sinTokens(mensaje: mensaje)
        default:
            let env = try? Self.decoder.decode(ErrorEnvelope.self, from: data)
            throw APIError.servidor(
                codigo: env?.error.code ?? "\(http.statusCode)",
                mensaje: env?.error.message ?? "Algo salió mal (\(http.statusCode)). Intenta de nuevo.")
        }
    }
}
