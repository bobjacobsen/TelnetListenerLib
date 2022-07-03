//
//  TelnetClientConnection.swift
//  TelnetListenerLib
//
//  Created by Bob Jacobsen on 7/1/22.
//

import Foundation
import Network
import os

public class TelnetClientConnection {
    let logger = Logger(subsystem: "org.ardenwood.TelnetListenerLib", category: "TelnetClientConnection")

    let  nwConnection: NWConnection
    let queue = DispatchQueue(label: "Client connection Q")
    
    public var receivedDataCallback : (_ : String) -> ()  // argument is the received text
 
    public init(nwConnection: NWConnection) {
        self.nwConnection = nwConnection
        receivedDataCallback = TelnetClientConnection.dummyCallback
    }
    
    static func dummyCallback(_ : String) {}  // to have something to initialize into receivedDataCallback by default
    
    var didStopCallback: ((Error?) -> Void)? = nil
    
    func start() {
        logger.info("connection will start")
        nwConnection.stateUpdateHandler = stateDidChange(to:)
        setupReceive()
        nwConnection.start(queue: queue)
    }
    
    private func stateDidChange(to state: NWConnection.State) {
        switch state {
        case .waiting(let error):
            logger.info("Client connection waiting")
            connectionDidFail(error: error)
        case .ready:
            logger.info("Client connection ready")
        case .failed(let error):
            logger.info("Client connection failed")
            connectionDidFail(error: error)
        default:
            logger.info("Client connection transition with extra state")
            break
        }
    }

    private func setupReceive() {
        nwConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { (data, _, isComplete, error) in
            if let data, !data.isEmpty {
                
                // THIS IS WHERE DATA IS RECEIVED
                // might be part of a line, full line, or multiple lines
                
                let message = String(data: data, encoding: .utf8) ?? "<unknown>"
                                
                // self.logger.debug("connection did receive, data: \(data as NSData) string: \(message)")
                DispatchQueue.main.async {   // from Naked Networking
                    // This is where the line is sent into the attached code
                    self.receivedDataCallback(message)
                }
            }
            if isComplete {
                self.logger.info("setupReceive isComplete")
                self.connectionDidEnd()
            } else if let error = error {
                self.logger.info("setupReceive error \(error, privacy: .public)")
                self.connectionDidFail(error: error)
            } else {
                self.setupReceive()
            }
        }
    }
    
    func send(data: Data) {
        nwConnection.send(content: data, completion: .contentProcessed( { error in
            if let error = error {
                self.connectionDidFail(error: error)
                return
            }
            // self.logger.debug("connection did send, data: \(data as NSData)")
        }))
    }
    
    func stop() {
        logger.info("connection will stop")
        stop(error: nil)
    }
    
    private func connectionDidFail(error: Error) {
        logger.info("connection did fail, error: \(error)")
        self.stop(error: error)
    }
    
    private func connectionDidEnd() {
        logger.info("connection did end")
        self.stop(error: nil)
    }
    
    private func stop(error: Error?) {
        self.nwConnection.stateUpdateHandler = nil
        self.nwConnection.cancel()
        if let didStopCallback = self.didStopCallback {
            self.didStopCallback = nil
            didStopCallback(error)
        }
    }
}

