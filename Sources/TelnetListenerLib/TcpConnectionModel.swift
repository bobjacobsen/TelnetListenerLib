//
//  TcpConnectionModel.swift
//  
//
//  Created by Bob Jacobsen on 9/12/22.
//

import Foundation
import Network
import os

final public class TcpConnectionModel : ObservableObject {
    public init() {
        self.browserhandler = SamplePeerBrowserDelegate()
        self.browser = PeerBrowser(delegate: self.browserhandler) // starts automatically
    }
    
    public let browserhandler : SamplePeerBrowserDelegate
    public let browser : PeerBrowser
    
    var serviceName : String = SamplePeerBrowserDelegate.PeerBrowserDelegateNoHubSelected
    var hostName :   String = ""
    var portNumber : UInt16 = 0
    var receivedDataCallback : ((String) -> ())! = nil
    var startUpCallback : (() -> ())! = nil
    
    // status flags
    public private(set) var loaded :        Bool = false
    public private(set) var started :       Bool = false
    public private(set) var ready :         Bool = false
    public private(set) var mDnsConnection: Bool = false
    
    let logger = Logger(subsystem: "us.ardenwood.TcpConnectionModel", category: "TcpConnectionModel")

    let logSendAndReceive = false  // set true for detailed logging
    
    /// Contains the human-readable status of the connection.
    @Published public var statusString : String = "Starting up..."
    
    /// Set up the connection parameters.
    /// - parameters:
    ///   - hostName: Name or IP address of the desired destination host
    ///   - portnumber: Port number for the connection, between 1 and 64k.
    ///   - receivedDataCallback: called with received Strings as they arribve. Do not expect any particular grouping of the characters.
    ///   - startUpCallback - invoked once after the first `start` once the connection is in `ready` state.

    public func load(serviceName: String, hostName : String, portNumber : UInt16, receivedDataCallback : ((String) -> ())!,  startUpCallback : (() -> ())!) {
        guard !loaded else { logger.error("Only call load() once"); return}
        self.serviceName = serviceName
        self.hostName = hostName
        self.portNumber = portNumber
        self.receivedDataCallback = receivedDataCallback
        self.startUpCallback = startUpCallback
        
        self.host = NWEndpoint.Host(hostName)
        self.port = NWEndpoint.Port(rawValue: portNumber)
        
        loaded = true
    }
    
    /// Reset the host name and port number.  This can be used after a `start` operation,
    ///  in which case it should be followed by `stop` and `start`
    public func retarget(serviceName: String, hostName : String, portNumber : UInt16) {
        self.serviceName = serviceName
        self.hostName = hostName
        self.portNumber = portNumber
        
        self.host = NWEndpoint.Host(hostName)
        self.port = NWEndpoint.Port(rawValue: portNumber)

    }
    
    /// Open and start up the connection
    public func start() {
        guard loaded else { logger.error("start() without being loaded"); return}
        guard !started else { logger.warning("start() while connected"); return}
        
        // open new connection
        started = true
        
        logger.debug("Starting with \"\(self.serviceName, privacy: .public)\" and \"\(self.hostName, privacy: .public)\"")
        if (serviceName != SamplePeerBrowserDelegate.PeerBrowserDelegateNoHubSelected) {
            logger.debug("start service-based connection")
            mDnsConnection = true
            // find the service from the name
            for endpoint in browserhandler.destinations {
                if (serviceName == endpoint.name) {
                    logger.trace("   name matched, connecting")
                    if endpoint.result != nil {
                        nwConnection = NWConnection(to: endpoint.result!.endpoint, using: .tcp)
                        break
                    }
                }
                // TODO: Is no-match handling needed here?
            }
        } else {
            logger.debug("start direct TCP connection")
            mDnsConnection = false
            nwConnection = NWConnection(host: self.host, port: self.port, using: .tcp)
        }
        nwConnection.stateUpdateHandler = stateUpdateHandler(to:)
        
        self.nwConnection.start(queue: queue)
        
        // start receive loop
        setupReceive()
    }

    /// Stop the connection.  Should be used only once after a `start` operation.
    public func stop() {
        logger.info("stop")
        guard loaded else { logger.error("stop() without being loaded"); return}
        guard started else { logger.warning("stop() without being connected"); return}
        
        started = false
        //self.nwConnection.stateUpdateHandler = nil
        logger.debug("      calling cancel")
        self.nwConnection.cancel()
    }
    
    /// Send  a String over an open connection
    public func send(string : String) {
        guard started else { logger.warning("send() without being connected"); return}
        let data = string.data(using: .utf8) ?? "<non UTF data>".data(using: .utf8)!
        send(data: data)
    }
    
    /// Send Data over an open connection
    public func send(data : Data) {
        guard loaded else { logger.error("send() without being loaded"); return}
        guard started else { logger.warning("send() without being connected"); return}

        nwConnection.send(content: data, completion: .contentProcessed( { error in
            if let error = error {
                self.connectionDidFail(error: error)
                return
            }
            if (self.logSendAndReceive) {
                self.logger.trace("connection did send, data: \(String(data: data, encoding: .utf8)!, privacy:.public)")
            }
        }))

    }
    
    // MARK: end of public interface
    
    var host : NWEndpoint.Host! = nil
    var port : NWEndpoint.Port! = nil
    var nwConnection: NWConnection! = nil
    
    let queue = DispatchQueue(label: "Client connection Q")

    // called from send(..) on error
    private func connectionDidFail(error: NWError) {
        logger.error("connection did fail, error: \(error.localizedDescription, privacy:.public)")
    }
    
    private func setupReceive() {
        nwConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { (data, _, isComplete, error) in
            if let data, !data.isEmpty {
                
                // THIS IS WHERE DATA IS RECEIVED
                // Might be part of a line, full line, or multiple lines
                
                let message = String(data: data, encoding: .utf8) ?? "<unknown>"
                
                DispatchQueue.main.async {   // from Naked Networking
                    // This is where the line is sent into the attached code
                    if (self.logSendAndReceive) {
                        self.logger.trace("connection did receive, data: \(message, privacy:.public)")
                    }
                    self.receivedDataCallback(message)
                }
            }
            if isComplete {
                self.logger.trace("setupReceive isComplete, connection is ending")
            } else if let error = error {
                self.logger.warning("setupReceive error \(error.localizedDescription, privacy:.public)")
                self.connectionDidFail(error: error)
            } else {
                // OK, repeat this operation
                self.setupReceive()
            }
        }
    }

    var lastSeenState : NWConnection.State! = nil
    
    private func stateUpdateHandler(to state: NWConnection.State) {
        lastSeenState = state
        
        switch state {
        case .setup:
            logger.info("entered setup")
            ready = false
            updateStatus(to: "Setup")
            return
        case .waiting(let error):
            logger.info("entered waiting \(error.localizedDescription, privacy:.public)")
            ready = false
            updateStatus(to: "Waiting For Connection")
            return
        case .preparing:
            logger.info("entered preparing")
            ready = false
            updateStatus(to: "Preparing For Connection")
            return
        case .ready:
            logger.info("entered ready")
            ready = true
            let status = mDnsConnection ? serviceName : hostName
            updateStatus(to: "Connected to \(status)")

            // if there's a startUpCallback, invoke it
            if startUpCallback != nil {
                startUpCallback()
                startUpCallback = nil // only execute the very first time
            }
            return
        case .failed(let error):
            logger.info("entered waiting \(error.localizedDescription, privacy:.public)")
            ready = false
            updateStatus(to: "Connection Failed \(error)")
            return
        case .cancelled:
            logger.info("entered cancelled")
            ready = false
            updateStatus(to: "Connection Dropped")
            return
        default:
            logger.info("entered some other state")
            ready = false
            updateStatus(to: "Unknown State")
            return
        }
    }

    private func updateStatus(to : String) {
        DispatchQueue.main.async{ // to avoid "publishing changes from within view updates is not allowed"
            self.statusString = to
        }
    }
}

// MARK: mDNS/Bonjour code

public struct BrowserFoundEndpoint : Hashable {
    public init(result: NWBrowser.Result?, name: String) {
        self.result = result
        self.name = name
    }
    public let result : NWBrowser.Result?
    public let name : String
    public let id = UUID()
}

public class SamplePeerBrowserDelegate : PeerBrowserDelegate {
    static public let PeerBrowserDelegateNoHubSelected = "<No Hub Selected>"
    @Published public var destinations : [BrowserFoundEndpoint] = [BrowserFoundEndpoint(result: nil, name: PeerBrowserDelegateNoHubSelected)]
    func refreshResults(results: Set<NWBrowser.Result>) {
        print ("refresh results")
        for item in results {
            print("    \(item.endpoint)")
            let serviceName = item.endpoint.debugDescription.replacingOccurrences(of: "._openlcb-can._tcplocal.", with: "")
            destinations.append(BrowserFoundEndpoint(result: item, name: serviceName))
        }
    }
    func displayBrowseError(_ error: NWError) {
        print ("browse error: \(error.localizedDescription)")
    }
}
