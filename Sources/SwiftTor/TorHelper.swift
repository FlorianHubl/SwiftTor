
import Foundation
import Tor

protocol OnionManagerDelegate: AnyObject {
    func torConnProgress(_ progress: Int)
    func torConnFinished()
    func torConnDifficulties()
}

public enum TorState: String {
    case none
    case started
    case connected
    case stopped
    case refreshing
}

@available(iOS 13.0, macOS 13, *)
class TorHelper: NSObject, URLSessionDelegate, ObservableObject {
    
    @Published public var state: TorState = .none
    public var cert: Data?
    private var config: TorConfiguration = TorConfiguration()
    private var thread: TorThread?
    private var controller: TorController?
    private var authDirPath = ""
    var isRefreshing = false
    
    var onionAddress: String?
    
    var hiddenServicePort: Int? = nil
    
    // The tor url session configuration.
    // Start with default config as fallback.
    private lazy var sessionConfiguration: URLSessionConfiguration = .default
    
    // The tor client url session including the tor configuration.
    lazy var session = URLSession(configuration: sessionConfiguration)
    
    private func removeLastPathComponent(from urlString: String) -> String? {
        if let url = URL(string: urlString) {
            if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if let path = components.path as NSString? {
                    let lastPathComponent = path.lastPathComponent
                    if path.length > lastPathComponent.count {
                        let newPath = path.deletingLastPathComponent
                        components.path = newPath
                        return components.string
                    }
                }
            }
        }
        return nil
    }
    
    func removeNewlines(from inputString: String) -> String {
        let cleanedString = inputString.replacingOccurrences(of: "\n", with: "")
        return cleanedString
    }

    // Start the tor client.
    func start(delegate: OnionManagerDelegate?) {
        //session.delegate = self
        weak var weakDelegate = delegate
        state = .started
        
        var proxyPort = 19050
        var dnsPort = 12345
#if targetEnvironment(simulator)
        proxyPort = 19052
        dnsPort = 12347
#endif
        
        sessionConfiguration.connectionProxyDictionary = [kCFProxyTypeKey: kCFProxyTypeSOCKS,
                                          kCFStreamPropertySOCKSProxyHost: "localhost",
                                          kCFStreamPropertySOCKSProxyPort: proxyPort]
        
        session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: .main)
        
#if targetEnvironment(macCatalyst)
        // Code specific to Mac.
#else
        // Code to exclude from Mac.
        session.configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
#endif
        
        //add V3 auth keys to ClientOnionAuthDir if any exist
        createTorDirectory()
        authDirPath = createAuthDirectory()
        
        clearAuthKeys { [weak self] in
            guard let self = self else { return }
            
            
            self.thread = nil
            
            self.config.options = [
                "DNSPort": "\(dnsPort)",
                "AutomapHostsOnResolve": "1",
                "SocksPort": "\(proxyPort)",//OnionTrafficOnly
                "AvoidDiskWrites": "1",
                "ClientOnionAuthDir": "\(self.authDirPath)",
                "LearnCircuitBuildTimeout": "1",
                "NumEntryGuards": "8",
                "SafeSocks": "1",
                "LongLivedPorts": "80,443",
                "NumCPUs": "2",
                "DisableDebuggerAttachment": "1",
                "SafeLogging": "1"
                //"ExcludeExitNodes": "1",
                //"StrictNodes": "1"
            ]
            
            self.config.cookieAuthentication = true
            
//            try? FileManager.default.createDirectory(at: URL(filePath: "\(self.torPath())/cp"), withIntermediateDirectories: false)
            
            if let port = hiddenServicePort {
                let torrcFile = """
HiddenServiceDir \(self.torPath())
HiddenServicePort 80 127.0.0.1:\(port)
"""
                FileManager.default.createFile(atPath: "\(self.torPath())/.torrc", contents: torrcFile.data(using: .utf8), attributes: [FileAttributeKey.posixPermissions: 0o700])
            }else {
                let torrcFile = """
"""
                FileManager.default.createFile(atPath: "\(self.torPath())/.torrc", contents: torrcFile.data(using: .utf8), attributes: [FileAttributeKey.posixPermissions: 0o700])
            }
            let torrcFile = try! String(contentsOfFile: "\(self.torPath())/.torrc")
            if torrcFile.isEmpty {
                print("torrcFile is empty")
            }else {
                print("Content of torrcFile: \(torrcFile)")
            }
            self.config.dataDirectory = URL(fileURLWithPath: self.torPath())
            var torrcPath = "\(self.torPath())/.torrc"
            self.config.arguments = ["-f", "\(self.torPath())/.torrc"]
            self.config.controlSocket = self.config.dataDirectory?.appendingPathComponent("cp")
            self.thread = TorThread(configuration: self.config)
            
            // Initiate the controller.
            if self.controller == nil {
                self.controller = TorController(socketURL: self.config.controlSocket!)
            }
            
            // Start a tor thread.
            self.thread?.start()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if self.hiddenServicePort != nil {
                    do {
                        var hostname = try String(contentsOfFile: "\(self.torPath())/hostname")
                        hostname = self.removeNewlines(from: hostname)
                        self.onionAddress = hostname
                        if let port = self.hiddenServicePort {
                            print("SwiftTor: Tor Hidden Service on Port \(port) Onion Address for Hidden Service: \(hostname)")
                        }
                    }catch {
                        print("SwiftTor: Onion Address for Tor Hidden Service couldnt be loaded \(error.localizedDescription)")
                    }
                }
                // Connect Tor controller.
                do {
                    if !(self.controller?.isConnected ?? false) {
                        do {
                            try self.controller?.connect()
                        } catch {
                            print("error=\(error)")
                        }
                    }
                    
                    let cookie = try Data(
                        contentsOf: self.config.dataDirectory!.appendingPathComponent("control_auth_cookie"),
                        options: NSData.ReadingOptions(rawValue: 0)
                    )
                    
                    self.controller?.authenticate(with: cookie) { (success, error) in
                        if let error = error {
                            print("error = \(error.localizedDescription)")
                            return
                        }
                        
                        var progressObs: Any? = nil
                        progressObs = self.controller?.addObserver(forStatusEvents: {
                            (type: String, severity: String, action: String, arguments: [String : String]?) -> Bool in
                            if arguments != nil {
                                if arguments!["PROGRESS"] != nil {
                                    let progress = Int(arguments!["PROGRESS"]!)!
                                    weakDelegate?.torConnProgress(progress)
                                    if progress >= 100 {
                                        self.controller?.removeObserver(progressObs)
                                    }
                                    return true
                                }
                            }
                            return false
                        })
                        
                        var observer: Any? = nil
                        observer = self.controller?.addObserver(forCircuitEstablished: { established in
                            if established {
                                self.state = .connected
                                weakDelegate?.torConnFinished()
                                self.controller?.removeObserver(observer)
                                
                            } else if self.state == .refreshing {
                                self.state = .connected
                                weakDelegate?.torConnFinished()
                                self.controller?.removeObserver(observer)
                            }
                        })
                    }
                } catch {
                    weakDelegate?.torConnDifficulties()
                    self.state = .none
                }
            }
        }
    }
    
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let trust = challenge.protectionSpace.serverTrust else {
            return
        }
        
        let credential = URLCredential(trust: trust)
        
        if let certData = self.cert,
           let remoteCert = SecTrustGetCertificateAtIndex(trust, 0) {
            let remoteCertData = SecCertificateCopyData(remoteCert) as NSData
            let certData = Data(base64Encoded: certData)
            
            if let pinnedCertData = certData,
               remoteCertData.isEqual(to: pinnedCertData as Data) {
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.rejectProtectionSpace, nil)
            }
        } else {
            completionHandler(.useCredential, credential)
        }
    }
    
    func resign() {
        controller?.disconnect()
        controller = nil
        thread?.cancel()
        thread = nil
        clearAuthKeys {}
        state = .stopped
    }
    
    private func createTorDirectory() {
        do {
            try FileManager.default.createDirectory(atPath: self.torPath(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [FileAttributeKey.posixPermissions: 0o700])
        } catch {
            print("Directory previously created.")
        }
//        addTorrc()
//        createHiddenServiceDirectory()
    }
    
    private func torPath() -> String {
#if targetEnvironment(simulator)
        let path = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? ""
        return "\(path.split(separator: Character("/"))[0..<2].joined(separator: "/"))/tor"
#else
        return "\(NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? "")/tor"
#endif
    }
    
//    private func addTorrc() {
//#if targetEnvironment(macCatalyst)
//        // Code specific to Mac.
//        let torrcUrl = URL(fileURLWithPath: "/Users/\(NSUserName())/Library/Containers/com.fontaine.fullynodedmacos/Data/.torrc")
//        let torrc = Torrc.torrc.dataUsingUTF8StringEncoding
//        do {
//            try torrc.write(to: torrcUrl)
//        } catch {
//            print("an error happened while creating the file")
//        }
//#elseif targetEnvironment(simulator)
//#else
//        let sourceURL = Bundle.main.bundleURL.appendingPathComponent("tor.torrc")
//        let torrc = try? String(contentsOf: sourceURL, encoding: .utf8)
//        print("sourceURL: \(sourceURL)")
//        print("torrc: \(torrc)")
//#endif
//    }
    
//    private func createHiddenServiceDirectory() {
//        do {
//            try FileManager.default.createDirectory(atPath: "\(torPath())/host",
//                                                    withIntermediateDirectories: true,
//                                                    attributes: [FileAttributeKey.posixPermissions: 0o700])
//        } catch {
//            print("Directory previously created.")
//        }
//    }
    
//    func hostname() -> String? {
//        let path = URL(fileURLWithPath: "/Users/\(NSUserName())/Library/Containers/com.fontaine.fullynodedmacos/Data/Library/Caches/tor/host/hostname")
//        return try? String(contentsOf: path, encoding: .utf8)
//    }
    
    private func createAuthDirectory() -> String {
        // Create tor v3 auth directory if it does not yet exist
        let authPath = URL(fileURLWithPath: self.torPath(), isDirectory: true).appendingPathComponent("onion_auth", isDirectory: true).path
        
        do {
            try FileManager.default.createDirectory(atPath: authPath,
                                                    withIntermediateDirectories: true,
                                                    attributes: [FileAttributeKey.posixPermissions: 0o700])
        } catch {
            print("Auth directory previously created.")
        }
        
        return authPath
    }
    
    
    private func clearAuthKeys(completion: @escaping () -> Void) {
        let fileManager = FileManager.default
        let authPath = self.authDirPath
        
        do {
            let filePaths = try fileManager.contentsOfDirectory(atPath: authPath)
            
            for filePath in filePaths {
                let url = URL(fileURLWithPath: authPath + "/" + filePath)
                try fileManager.removeItem(at: url)
            }
            
            completion()
        } catch {
            
            completion()
        }
    }
    
    func turnedOff() -> Bool {
        return false
    }
}

public struct AuthKeysStruct: CustomStringConvertible {
    public var description = ""
    let privateKey:Data
    let publicKey:String
    let id:UUID
    init(dictionary: [String:Any]) {
        privateKey = dictionary["privateKey"] as! Data
        publicKey = dictionary["publicKey"] as! String
        id = dictionary["id"] as! UUID
    }
}


