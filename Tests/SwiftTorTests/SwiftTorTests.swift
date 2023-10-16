import XCTest
@testable import SwiftTor

final class SwiftTorTests: XCTestCase {
    @available(iOS 16.0.0, macOS 10.15, *)
    func test() async throws {
        let tor = SwiftTor()
        let request = URLRequest(url: URL(string: "https://check.torproject.org")!)
        try await Task.sleep(for: .seconds(7))
        if tor.state == .connected {
            print("Tor Connected")
            let a = try await tor.request(request: request).0
            print(String(data: a, encoding: .utf8)!)
        }else {
            print("Tor not Connected")
        }
    }
}
