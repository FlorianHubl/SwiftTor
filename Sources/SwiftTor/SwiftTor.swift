import Tor

@available(iOS 13.0, *)
public class SwiftTor: ObservableObject {
    private let tor: TorHelper
    
    @Published public var state = TorState.none
    
    public init() {
        self.tor = TorHelper()
        tor.start(delegate: nil)
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            self.state = self.tor.state
        }
    }
    
    enum TorError: Error {
        case notConnected
    }
    
    public func restart() {
        tor.start(delegate: nil)
    }
    
    public func request(request: URLRequest) async throws -> (Data, URLResponse) {
        if self.tor.state == .connected {
            return try! await tor.session.data(for: request)
        }else {
            throw TorError.notConnected
        }
    }
}
