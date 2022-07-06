//
//  TelnetClient.swift
//  
//
//  Created by Bob Jacobsen on 7/1/22.
//

import Foundation
import Network
import os

public class TelnetClient {
    public let connection : TelnetClientConnection
    let host : NWEndpoint.Host
    let port : NWEndpoint.Port
    
    let logger = Logger(subsystem: "org.ardenwood.TelnetListenerLib", category: "TelnetClient")
    
    public init(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
        let nwConnection = NWConnection(host: self.host, port: self.port, using: .tcp)
        connection = TelnetClientConnection(nwConnection: nwConnection)
        
        logger.info("TelnetClientConnection created \(host) \(port)")
    }
    
    public func start() {
        logger.info("TelnetClient started")
        connection.didStopCallback = didStopCallback(error:)
        connection.start()
    }
    
    public func stop() {
        connection.stop()
    }
    
    public func sendString(string: String) {
        send(data: string.data(using: .utf8) ?? Data()) // if can't parse with UTF8, just ignore it
    }
    
    public func send(data: Data) {
        connection.send(data: data)
    }
    
    public func didStopCallback(error: Error?) {
        if error == nil {
            // exit(EXIT_SUCCESS)
            logger.info("Connection exited with SUCCESS")
        } else {
            // exit(EXIT_FAILURE)
            logger.info("Connection exited with ERROR: \(error!, privacy: .public)")
        }
    }
}
