import XCTest
@testable import PasteTrail

final class GumroadLicenseValidatorTests: XCTestCase {

    // MARK: - formEncode (via validate — we test observable side effects through the public API)

    /// An empty key should still reach the network layer; the test exercises the error path
    /// by using an obviously invalid key against a mock URLSession.
    func testValidateThrowsInvalidKeyOnFailureResponse() async {
        // Inject a URLSession that returns {"success": false}
        let session = makeMockSession(json: ["success": false])
        do {
            try await GumroadLicenseValidator.validate(key: "BAD-KEY", session: session)
            XCTFail("Expected GumroadError.invalidKey to be thrown")
        } catch GumroadError.invalidKey {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidateSucceedsOnSuccessResponse() async throws {
        let session = makeMockSession(json: ["success": true])
        // Should not throw
        try await GumroadLicenseValidator.validate(key: "GOOD-KEY", session: session)
    }

    func testValidateThrowsNetworkErrorOnURLSessionFailure() async {
        let session = makeMockSession(error: URLError(.notConnectedToInternet))
        do {
            try await GumroadLicenseValidator.validate(key: "ANY-KEY", session: session)
            XCTFail("Expected GumroadError.networkError to be thrown")
        } catch GumroadError.networkError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func makeMockSession(json: [String: Any]) -> URLSession {
        let data = try! JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(url: URL(string: "https://api.gumroad.com")!,
                                       statusCode: 200,
                                       httpVersion: nil,
                                       headerFields: nil)!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.stub = .success(data: data, response: response)
        return URLSession(configuration: config)
    }

    private func makeMockSession(error: Error) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.stub = .failure(error)
        return URLSession(configuration: config)
    }
}

// MARK: - MockURLProtocol

private class MockURLProtocol: URLProtocol {

    enum Stub {
        case success(data: Data, response: URLResponse)
        case failure(Error)
    }

    static var stub: Stub = .failure(URLError(.unknown))

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch Self.stub {
        case .success(let data, let response):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
