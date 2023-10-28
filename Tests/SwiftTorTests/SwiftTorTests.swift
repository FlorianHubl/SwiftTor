import XCTest
@testable import SwiftTor

final class SwiftTorTests: XCTestCase {
    @available(iOS 16.0.0, macOS 10.15, *)
    func test() async throws {
        let tor = SwiftTor(hiddenServicePort: 80)
        let request = URLRequest(url: URL(string: "https://check.torproject.org")!)
        let a = try await tor.request(request: request).0
        print(String(data: a, encoding: .utf8)!)
        Timer.scheduledTimer(withTimeInterval: 3.7, repeats: false) { _ in
            print(tor.onionAddress ?? "No onion address")
        }
    }
}
