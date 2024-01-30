# SwiftTor

Create a URLSession through Tor and access .onion websites. This Swift Package is a simple Tor Client with the Tor Framework.

<img src="https://github.com/FlorianHubl/SwiftTor/blob/main/SwiftTor.png" width="173" height="173">

### Allow Tor connections

To allow tor connections please enable the arbitrary loads in the app transport security settings.

<img src="https://github.com/FlorianHubl/SwiftTor/blob/main/allow.png" width="173">

SwiftTor is available for iOS and macOS.

### macOS

If you use SwiftTor on macOS make sure you activate incoming and outgoing Connections.

<img src="https://github.com/FlorianHubl/SwiftTor/blob/main/allow2.png" width="173">

## Documentation

### Create a instance

```swift
let tor = SwiftTor()
```

### Check the connection

```swift
if tor.state == .connected {
    // connected
}else {
    // not connected
}
```

### Do a http request on a onion address

```swift
let onionAddress = "http://mempoolhqx4isw62xs7abwphsq7ldayuidyx2v2oethdhhj6mlo2r6ad.onion/api/v1/fees/recommended"
let url = URL(string: onionAddress)!
let request = URLRequest(url: url)
let result = try! await tor.request(request: request)
```

### Tor Hidden Service
```swift
let tor = SwiftTor(hiddenServicePort: 80)
Timer.scheduledTimer(withTimeInterval: 3.7, repeats: false) { _ in
    print(tor.onionAddress ?? "No onion address")
}
```


### Example in SwiftUI

```swift
import SwiftUI
import SwiftTor

struct ContentView: View {
    
    @StateObject var tor = SwiftTor()
    
    @State private var text = ""
    
    @State private var time = 0.0
    
    @State private var requesting = false
    
    var body: some View {
        VStack {
            Text("Time: \(time) seconds")
            Text(text)
            Text(tor.state == .connected ? "Tor Connected" : "Tor not connected")
                .foregroundColor(tor.state == .connected ? .green : .red)
            Button("Tor Request", action: request)
        }
    }
    
    func request() {
        guard tor.state == .connected else {return}
        guard self.requesting == false else {return}
        self.text = ""
        self.requesting = true
        self.time = 0.0
        Task {
            let time1 = Date().timeIntervalSince1970
            let onionAddress = "http://mempoolhqx4isw62xs7abwphsq7ldayuidyx2v2oethdhhj6mlo2r6ad.onion/api/v1/fees/recommended"
            let url = URL(string: onionAddress)!
            let request = URLRequest(url: url)
            let result = try! await tor.request(request: request)
            let time2 = Date().timeIntervalSince1970
            self.time = time2 - time1
            text = String(data: result.0, encoding: .utf8)!
            self.requesting = false
        }
    }
}
```
