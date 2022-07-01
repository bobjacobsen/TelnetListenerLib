import Network

public struct TelnetListenerLib {
    let connection: TelnetClientConnection
    let host: NWEndpoint.Host
    let port: NWEndpoint.Port
    public init(host: String, port: UInt16) {
        // sample init to show compilation
        
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
        let nwConnection = NWConnection(host: self.host, port: self.port, using: .tcp)
        connection = TelnetClientConnection(nwConnection: nwConnection)

    }
}
