# SwiftTor

Create a URLSession through Tor and access .onion websites. This Swift Package is a simple Tor Client with the Tor Framework.

<img src="https://github.com/FlorianHubl/SwiftTor/blob/main/SwiftTor.png" width="173" height="173">

## Documentation

### Create a instance

´´´swift
let tor = SwiftTor()
´´´

### Check the connection

´´´swift
if tor.state == .connected {
    // connected
}else {
    // not connected
}
´´´

### Do a http request on a onion address

´´´swift
let onionAddress = "http://mempoolhqx4isw62xs7abwphsq7ldayuidyx2v2oethdhhj6mlo2r6ad.onion/api/v1/fees/recommended"
let url = URL(string: onionAddress)!
let request = URLRequest(url: url)
let a = try! await tor.request(request: request)
´´´
