import Foundation
import XCTest
@testable import shuttle

/// Exercises the actual URLSession transport without contacting a daemon.
final class SpindleClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.configure { _ in throw URLError(.badServerResponse) }
        super.tearDown()
    }

    private func client(token: String = "unit-test-token") -> SpindleClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return SpindleClient(
            baseURL: URL(string: "https://example.invalid/spindle/")!,
            token: token,
            session: URLSession(configuration: configuration)
        )
    }

    func testAllReadOnlyEndpointsUseGETAndDecodeFixtures() async throws {
        let status = try Fixtures.data("status")
        let queue = try Fixtures.data("queue")
        let item = try Fixtures.data("item")
        let logs = try Fixtures.data("logs")
        StubURLProtocol.configure { request in
            switch request.url?.path {
            case "/spindle/api/health": return (200, Data(#"{"status":"ok"}"#.utf8))
            case "/spindle/api/status": return (200, status)
            case "/spindle/api/queue": return (200, queue)
            case "/spindle/api/queue/21": return (200, item)
            case "/spindle/api/logs": return (200, logs)
            default: throw URLError(.badURL)
            }
        }
        let api = client()

        try await api.health()
        let receivedStatus = try await api.status()
        let receivedQueue = try await api.queue()
        let receivedItem = try await api.item(id: 21)
        let query = LogQuery(since: 42, limit: 20, tail: true, itemID: 21, minimumLevel: .warn, component: "disc monitor", daemonOnly: true)
        let receivedLogs = try await api.logs(query)
        XCTAssertEqual(receivedStatus.pid, try Fixtures.status().pid)
        XCTAssertEqual(receivedQueue.count, 24)
        XCTAssertEqual(receivedItem.id, 21)
        XCTAssertEqual(receivedLogs.next, 255)

        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.compactMap { $0.url?.path }, [
            "/spindle/api/health", "/spindle/api/status", "/spindle/api/queue", "/spindle/api/queue/21", "/spindle/api/logs",
        ])
        for request in requests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-token")
        }
        let url = try XCTUnwrap(requests.last?.url)
        let parameters = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.value ?? "") }), [
            "since": "42", "limit": "20", "tail": "1", "item": "21", "level": "warn", "component": "disc monitor", "daemon_only": "1",
        ])
    }

    func testEmptyTokenOmitsAuthorizationAndUnfilteredLogsHaveNoQuery() async throws {
        StubURLProtocol.configure { _ in (200, Data(#"{"events":[],"next":0}"#.utf8)) }
        _ = try await client(token: "").logs(LogQuery())
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(try XCTUnwrap(request.url).query)
    }

    func testUnauthorizedAndHTTPFailuresHaveDistinctErrors() async throws {
        let api = client()
        for code in [401, 403, 500] {
            StubURLProtocol.configure { _ in (code, Data()) }
            do {
                _ = try await api.status()
                XCTFail("HTTP \(code) must fail")
            } catch let error as SpindleClientError {
                XCTAssertEqual(error, code == 500 ? .httpStatus(500) : .unauthorized)
            }
        }
    }

    func testMalformedJSONAndNetworkFailureAreReported() async throws {
        let api = client()
        StubURLProtocol.configure { _ in (200, Data(#"{"running":true}"#.utf8)) }
        do {
            _ = try await api.status()
            XCTFail("incomplete status must fail decoding")
        } catch let error as SpindleClientError {
            guard case .decoding(let detail) = error else { return XCTFail("expected decoding error: \(error)") }
            XCTAssertFalse(detail.isEmpty)
        }

        StubURLProtocol.configure { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await api.status()
            XCTFail("network failure must propagate")
        } catch let error as SpindleClientError {
            guard case .unreachable(let detail) = error else { return XCTFail("expected unreachable: \(error)") }
            XCTAssertFalse(detail.isEmpty)
        }
    }
}

/// URLSession calls this on its own thread; a lock protects the scripted
/// response and request log without sharing state with any live connection.
private final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    // Both properties are only accessed while holding lock (including URLSession's callback thread).
    nonisolated(unsafe) private static var response: (URLRequest) throws -> (Int, Data) = { _ in throw URLError(.badServerResponse) }
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    static func configure(_ handler: @escaping (URLRequest) throws -> (Int, Data)) {
        lock.lock()
        defer { lock.unlock() }
        response = handler
        recorded = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        let handler = Self.response
        Self.lock.unlock()
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
