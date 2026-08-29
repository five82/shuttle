import Foundation

/// The read-only subset of Spindle's HTTP API. Mutating endpoints are
/// deliberately not modeled, so nothing in the app can call them.
protocol SpindleAPI: Sendable {
    func health() async throws
    func status() async throws -> StatusResponse
    func queue() async throws -> [QueueItem]
    func item(id: Int64) async throws -> QueueItem
    func logs(since: UInt64?, limit: Int?, itemID: Int64?) async throws -> LogsResponse
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

    func logs(since: UInt64? = nil, limit: Int? = nil, itemID: Int64? = nil) async throws -> LogsResponse {
        var query: [URLQueryItem] = []
        if let since { query.append(URLQueryItem(name: "since", value: String(since))) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let itemID { query.append(URLQueryItem(name: "item", value: String(itemID))) }
        return try await get("/api/logs", query: query)
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
