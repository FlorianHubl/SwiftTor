import Tor

@available(iOS 13.0, *)
public class SwiftTor: ObservableObject {
    private var tor: TorHelper
    
    @Published public var state = TorState.none
    
    public init() {
        self.tor = TorHelper()
        tor.start(delegate: nil)
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            self.state = self.tor.state
        }
    }
    
    public func runAfterConnection(runAfterConnection: @escaping () -> ()) {
        if self.tor.state == .connected {
            runAfterConnection()
        }else {
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
                if self.tor.state == .connected {
                    runAfterConnection()
                    timer.invalidate()
                }
            }
        }
    }
    
    enum TorError: Error {
        case notConnected
    }
    
    public func restart() {
        self.state = .none
        self.tor = TorHelper()
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
