import Foundation

/// The read-only subset of Spindle's HTTP API. Mutating endpoints are
/// deliberately not modeled, so nothing in the app can call them.
protocol SpindleAPI: Sendable {
    func health() async throws
    func status() async throws -> StatusResponse
    func queue() async throws -> [QueueItem]
    func item(id: Int64) async throws -> QueueItem
    func logs(_ query: LogQuery) async throws -> LogsResponse
}

/// Read-only filters for `GET /api/logs`.
struct LogQuery: Equatable, Sendable {
    /// Cursor from a previous response's `next`; entries with seq >= since. nil = initial window.
    var since: UInt64? = nil
    var limit: Int? = nil
    /// Most recent entries first window; ignored by the daemon when `since` is set.
    var tail = false
    var itemID: Int64? = nil
    var minimumLevel: LogLevel? = nil
    var component: String? = nil
    var daemonOnly = false

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let since { items.append(URLQueryItem(name: "since", value: String(since))) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        if tail { items.append(URLQueryItem(name: "tail", value: "1")) }
        if let itemID { items.append(URLQueryItem(name: "item", value: String(itemID))) }
        if let minimumLevel { items.append(URLQueryItem(name: "level", value: minimumLevel.queryValue)) }
        if let component, !component.isEmpty { items.append(URLQueryItem(name: "component", value: component)) }
        if daemonOnly { items.append(URLQueryItem(name: "daemon_only", value: "1")) }
        return items
    }
}

enum SpindleClientError: LocalizedError, Equatable {
    case invalidURL(String)
    case unreachable(String)
    case unauthorized
    case httpStatus(Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let string): return "“\(string)” is not a valid Spindle address."
        case .unreachable(let reason): return "Spindle is unreachable: \(reason)"
        case .unauthorized: return "Spindle rejected the API token."
        case .httpStatus(let code): return "Spindle returned HTTP \(code)."
        case .decoding(let reason): return "Could not read Spindle's response: \(reason)"
        }
    }
}

struct SpindleClient: SpindleAPI {
    let baseURL: URL
    let token: String
    let session: URLSession

    init(baseURL: URL, token: String, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.token = token
        self.session = session ?? Self.makeSession()
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    func health() async throws {
        let _: HealthResponse = try await get("/api/health")
    }

    func status() async throws -> StatusResponse {
        try await get("/api/status")
    }

    func queue() async throws -> [QueueItem] {
        let envelope: QueueEnvelope = try await get("/api/queue")
        return envelope.items
    }

    func item(id: Int64) async throws -> QueueItem {
        let envelope: ItemEnvelope = try await get("/api/queue/\(id)")
        return envelope.item
    }

    func logs(_ query: LogQuery) async throws -> LogsResponse {
        try await get("/api/logs", query: query.queryItems)
    }

    // MARK: - Transport

    private struct HealthResponse: Decodable { var status: String }
    private struct QueueEnvelope: Decodable { var items: [QueueItem] }
    private struct ItemEnvelope: Decodable { var item: QueueItem }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw SpindleClientError.invalidURL(baseURL.absoluteString)
        }
        components.path = (components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path) + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw SpindleClientError.invalidURL(baseURL.absoluteString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw SpindleClientError.unreachable(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 401, 403: throw SpindleClientError.unauthorized
            default: throw SpindleClientError.httpStatus(http.statusCode)
            }
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SpindleClientError.decoding(String(describing: error))
        }
    }
}
