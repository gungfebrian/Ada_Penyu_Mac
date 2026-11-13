import XCTest
@testable import Ada_Penyu_Desktop

final class BackendStub: URLProtocol {
    nonisolated(unsafe) static var responseDelay: ((URLRequest) -> TimeInterval)?
    private let callbackLock = NSLock()
    private var stopped = false
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var captured = request
            if captured.httpBody == nil, let stream = captured.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    bytes.append(contentsOf: buffer.prefix(count))
                }
                captured.httpBodyStream = nil
                captured.httpBody = bytes
            }
            guard let handler = Self.handler else { throw URLError(.cancelled) }
            let (code, data) = try handler(captured)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            let deliver = { [self] in
                callbackLock.lock()
                let mayDeliver = !stopped
                callbackLock.unlock()
                guard mayDeliver else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
            if let delay = Self.responseDelay?(captured), delay > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: deliver)
            } else { deliver() }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { callbackLock.lock(); stopped = true; callbackLock.unlock() }
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BackendStub.self]
        return URLSession(configuration: config)
    }
}

@MainActor
final class BackendSessionTests: XCTestCase {
    func testSignedOutRequestsNeverAttemptAutomaticPasswordLogin() async {
        var requests = 0
        BackendStub.handler = { _ in requests += 1; throw URLError(.notConnectedToInternet) }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session())
        client.logout()
        do { let _: [String: String] = try await client.get("api/v2/individuals"); XCTFail("Signed out request succeeded") }
        catch { XCTAssertEqual(requests, 0) }
    }

    func testDefaultBackendIsHosted() {
        let domain = "BackendSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        XCTAssertEqual(APIConfig.currentURL(defaults: defaults).absoluteString, "https://api.donagondev.my.id")
    }
}
