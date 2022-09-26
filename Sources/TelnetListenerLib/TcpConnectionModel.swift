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
        self.browserhandler = ModelPeerBrowserDelegate()
        self.browser = PeerBrowser(delegate: self.browserhandler) // starts automatically
        
        browserhandler.parent = self
    }
    
    public let browserhandler : ModelPeerBrowserDelegate  // public access to retrieve values stored while handling browse operations
        
    // status flags
    public private(set) var loaded :        Bool = false
    public private(set) var started :       Bool = false
    public private(set) var ready :         Bool = false
    public private(set) var mDnsConnection: Bool = false
    
    let logSendAndReceive = false  // set true for really detailed logging
    
    /// Contains the human-readable status of the connection.
    @Published public var statusString : String = "Starting up..."
    
    /// Set up the connection parameters.
    /// - parameters:
    ///   - serviceName: Name of an mDNS/Bonjour service to find and use.  This takes prioirity over the hostname/port values unless this equals `SamplePeerBrowserDelegate.PeerBrowserDelegateNoHubSelected`
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
        retryCount = 0
    }
    
    /// Reset the service name, host name and port number.  This can be used after a `start` operation,
    ///  in which case it should be followed by `stop` and `start`
    public func retarget(serviceName: String, hostName : String, portNumber : UInt16) {
        self.serviceName = serviceName
        self.hostName = hostName
        self.portNumber = portNumber
        
        self.host = NWEndpoint.Host(hostName)
        self.port = NWEndpoint.Port(rawValue: portNumber)

        retryCount = 0
    }
    
    /// Open and start up the connection.
    public func start() {
        guard loaded else { logger.error("start() without being loaded"); return}
        guard !started else { logger.warning("start() while connected"); return}
        
        // open new connection
        started = true
        
        logger.debug("Starting with \"\(self.serviceName, privacy: .public)\" and \"\(self.hostName, privacy: .public)\"")
        if (serviceName != ModelPeerBrowserDelegate.PeerBrowserDelegateNoHubSelected) {
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
            }
            // did this succeed?  Might not if mDNS/Bonjour is delayed coming up
            if nwConnection == nil && retryCount < 8 {
                // Connection did not succeed, retry in a half-second
                retryCount += 1
                logger.warning("Will reattempt connection shortly")
                let deadlineTime = DispatchTime.now() + .milliseconds(500)
                DispatchQueue.main.asyncAfter(deadline: deadlineTime) {
                    self.logger.info("Reattempting connection")
                    self.stop()
                    self.start()
                }

            }
        } else {
            logger.debug("start direct TCP connection")
            mDnsConnection = false
            nwConnection = NWConnection(host: self.host, port: self.port, using: .tcp)
        }
        
        // did the connection creation succeed?
        if nwConnection != nil {
            nwConnection.stateUpdateHandler = stateUpdateHandler(to:)
            self.nwConnection.start(queue: queue)
            
            // start receive loop
            setupReceive()
        } else {
            logger.error("nwConnection not created, retry needed")
            updateStatus(to: "No hub found!")
        }
    }

    /// Stop the connection.  Should be used only once after a `start` operation.
    public func stop() {
        logger.info("stop")
        guard loaded else { logger.error("stop() without being loaded"); return}
        guard started else { logger.warning("stop() without being connected"); return}
        
        started = false
        logger.debug("      calling cancel")
        if (self.nwConnection != nil) { self.nwConnection.cancel() }
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
    
    internal let browser : PeerBrowser

    internal var serviceName : String = ModelPeerBrowserDelegate.PeerBrowserDelegateNoHubSelected
    internal var hostName :   String = ""
    internal var portNumber : UInt16 = 0
    internal var receivedDataCallback : ((String) -> ())! = nil
    internal var startUpCallback : (() -> ())! = nil

    var retryCount = 0  // number of service-open tries attempted
    
    private let logger = Logger(subsystem: "us.ardenwood.TelnetListenerLib", category: "TcpConnectionModel")

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

final public class ModelPeerBrowserDelegate : PeerBrowserDelegate, ObservableObject {
    var parent : TcpConnectionModel?
    
    static public let PeerBrowserDelegateNoHubSelected = "<No Hub Selected>"
    @Published public var destinations : [BrowserFoundEndpoint] = [BrowserFoundEndpoint(result: nil, name: PeerBrowserDelegateNoHubSelected)]
    private static let logger = Logger(subsystem: "us.ardenwood.TelnetListenerLib", category: "SamplePeerBrowserDelegate")

    private let logger = Logger(subsystem: "us.ardenwood.TelnetListenerLib", category: "ModelPeerBrowserDelegate")

    func refreshResults(results: Set<NWBrowser.Result>) {
        DispatchQueue.main.async{ // to avoid "publishing changes from within view updates is not allowed"
            ModelPeerBrowserDelegate.logger.trace("refresh Bonjour results")
            self.destinations = [BrowserFoundEndpoint(result: nil, name: ModelPeerBrowserDelegate.PeerBrowserDelegateNoHubSelected)]
            for item in results {
                ModelPeerBrowserDelegate.logger.trace("    \(item.endpoint.debugDescription)")
                let serviceName = item.endpoint.debugDescription.replacingOccurrences(of: "._openlcb-can._tcplocal.", with: "")
                self.destinations.append(BrowserFoundEndpoint(result: item, name: serviceName))
            }
            // notify
            self.parent!.objectWillChange.send()
        }
    }
    func displayBrowseError(_ error: NWError) {
        logger.error("browse error: \(error.localizedDescription, privacy: .public)")
    }
}
