import Tor

@available(iOS 13.0, macOS 13, *)
public class SwiftTor: ObservableObject {
    private var tor: TorHelper
    
    @Published public var state = TorState.none
    
    public init(hiddenServicePort: Int? = nil) {
        self.tor = TorHelper()
        self.tor.hiddenServicePort = hiddenServicePort
        tor.start(delegate: nil)
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            self.state = self.tor.state
        }
        if hiddenServicePort != nil {
            Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
                self.onionAddress = self.tor.onionAddress
            }
        }
    }
    
    @Published public var onionAddress: String? = nil
    
    enum TorError: Error {
        case notConnectedTimeout
    }
    
    public func restart() {
        self.state = .none
        self.tor = TorHelper()
        tor.start(delegate: nil)
    }
    
    public var session: URLSession {
        tor.session
    }
    
    private func doRequest(request: URLRequest, index: Int) async throws -> (Data, URLResponse) {
        if self.tor.state == .connected {
            return try await tor.session.data(for: request)
        }else {
            if index < 21 {
                try await Task.sleep(nanoseconds: 1000000000)
                return try await doRequest(request: request, index: index + 1)
            }else {
                throw TorError.notConnectedTimeout
            }
        }
    }
    
    public func request(request: URLRequest) async throws -> (Data, URLResponse) {
        try await doRequest(request: request, index: 1)
    }
}
