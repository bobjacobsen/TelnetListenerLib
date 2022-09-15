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
    
    let logger = Logger(subsystem: "us.ardenwood.TelnetListenerLib", category: "TelnetClient")
    
    public init(host: String, port: UInt16) {
        logger.trace("TelnetClient init \(host) \(port)")
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
        let nwConnection = NWConnection(host: self.host, port: self.port, using: .tcp)
        connection = TelnetClientConnection(nwConnection: nwConnection)
        connection.didStopCallback = didStopCallback(error:)

        logger.info("TelnetClient init complete")
    }
    
    public func setStopCallback(_ callback: @escaping ((any Error)?) -> Void ) {
        connection.didStopCallback = callback
    }
    public func start() {
        logger.trace("TelnetClient start")
        connection.start()
        logger.trace("TelnetClient started")
    }
    
    public func stop() {
        logger.trace("TelnetClient stop")
        connection.stop()
        logger.trace("TelnetClient stopped")
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
            logger.info("Connection exited with SUCCESS, restarting")
            
            let deadlineTime = DispatchTime.now() + .milliseconds(1000)
            DispatchQueue.main.asyncAfter(deadline: deadlineTime) {
                self.logger.info("   calling start after delay")
                self.start()
            }

        } else {
            // exit(EXIT_FAILURE)
            logger.error("Connection exited with ERROR: \(error!.localizedDescription, privacy: .public)")
        }
    }
}
