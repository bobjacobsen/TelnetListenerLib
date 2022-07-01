//
//  TelnetClient.swift
//  
//
//  Created by Bob Jacobsen on 7/1/22.
//

import Foundation
import Network

public class TelnetClient {
    let connection : TelnetClientConnection
    let host : NWEndpoint.Host
    let port : NWEndpoint.Port
    
    init(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
        let nwConnection = NWConnection(host: self.host, port: self.port, using: .tcp)
        connection = TelnetClientConnection(nwConnection: nwConnection)
    }
    
    func start() {
        print("Client started \(host) \(port)")
        connection.didStopCallback = didStopCallback(error:)
        connection.start()
    }
    
    func stop() {
        connection.stop()
    }
    
    func send(data: Data) {
        connection.send(data: data)
    }
    
    func didStopCallback(error: Error?) {
        if error == nil {
            exit(EXIT_SUCCESS)
        } else {
            exit(EXIT_FAILURE)
        }
    }
}
