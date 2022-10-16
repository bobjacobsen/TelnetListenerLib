import Network


/// Example of creating and starting a connection
public struct TelnetListenerLib {

    var selectedService  = ModelPeerBrowserDelegate.PeerBrowserDelegateNoHubSelected
    /// sample value to make a test connection
    var hostName :   String = "google.com"
    /// sample value to make a test connection
    var portNumber : UInt16 = 80
    
    func receivedDataCallback(data : String) -> () {
        // print ("Data received: \(data)")
    }
    
    /// Example of a startUp callback that just closes the connection. This is not something that a using package would do.
    func startUpCallback() -> () {
        // print ("Startup complete")
        
        // now do a stop
        connection.stop()
    }

    /// Example of a restart callback that just closes the connection. This is not something that a using package would do.
    func restartCallback() -> () {
        // print ("Restart complete")
        
        // now do a stop
        connection.stop()
    }

    let connection = TcpConnectionModel()

    public init() {
        connection.load(serviceName: selectedService, hostName: hostName, portNumber: portNumber, receivedDataCallback: receivedDataCallback,  startUpCallback: startUpCallback, restartCallback: restartCallback)
        
        connection.start()
    }
}
