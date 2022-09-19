import Network


/// Example of creating and starting a connection
public struct TelnetListenerLib {

    var selectedService  = SamplePeerBrowserDelegate.PeerBrowserDelegateNoHubSelected
    var hostName :   String = "google.com"
    var portNumber : UInt16 = 80
    
    func receivedDataCallback(data : String) -> () {
        print ("Data received: \(data)")
    }
    
    func startUpCallback() -> () {
        print ("Startup complete")
        
        // now do a stop
        connection.stop()
    }

    let connection = TcpConnectionModel()

    public init() {
        connection.load(serviceName: selectedService, hostName: hostName, portNumber: portNumber, receivedDataCallback: receivedDataCallback,  startUpCallback: startUpCallback)
        
        connection.start()
    }
}
