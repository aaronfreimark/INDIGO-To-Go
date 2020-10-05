//
//  IndigoConnection.swift
//  INDIGO Status
//
//  Created by Aaron Freimark on 9/18/20.
//

import Foundation
import Network
import SwiftyJSON

class IndigoConnection {
    
    var name = ""
    private var endpoint: NWEndpoint?
    private var serviceConnection: NWConnection?
    private var websocketConnection: NWConnection?
    private var parameters: NWParameters?

    var didStopCallback: ((Error?) -> Void)? = nil

    var delegate: IndigoConnectionDelegate?
    var queue: DispatchQueue
    
    var isUpgradedtoWebSockets = false

    
    init(name: String, endpoint: NWEndpoint, queue: DispatchQueue, delegate: IndigoConnectionDelegate) {
        self.name = name
        self.endpoint = endpoint
        self.queue = queue
        self.delegate = delegate
    }
    
    func start() {

        // first start with service endpoint, then check path for real endpoint, then connect with websocket endpoint
        self.parameters = NWParameters.tcp
        self.serviceConnection = NWConnection(to: self.endpoint!, using: self.parameters!)
        self.serviceConnection!.stateUpdateHandler = self.serviceConnectionStateDidChange(to:)
        self.serviceConnection!.start(queue: self.queue)

    }

    
    private func setupReceive() {
        self.websocketConnection!.receiveMessage { [weak self] (data, context, isComplete, error) in
            if let data = data, !data.isEmpty {
                self!.delegate!.receiveMessage(data: data, context: context, isComplete: isComplete, error: error)
            }
            if let error = error {
                self!.connectionDidFail(error: error)
            } else {
                self!.setupReceive()
            }
        }
    }

    // =================================================

    func serviceConnectionStateDidChange(to state: NWConnection.State) {
        switch state {
        case .ready:
            print("\(self.name): Service connected. Resolving endpoint and upgrading to websockets.")
            
            guard let websocketEndpoint = self.websocketEndpoint() else { return }
            self.endpoint = websocketEndpoint
                        
//            self.serviceConnection!.stateUpdateHandler = nil
            self.serviceConnection!.cancel()

            self.parameters!.allowLocalEndpointReuse = true
            self.parameters!.includePeerToPeer = true
            let websocketOptions = NWProtocolWebSocket.Options()
            websocketOptions.autoReplyPing = true
            self.parameters!.defaultProtocolStack.applicationProtocols.insert(websocketOptions, at: 0)
            
            print("\(self.name): Creating websocket connection.")
            self.websocketConnection = NWConnection(to: websocketEndpoint, using: self.parameters!)

            self.didStopCallback = didStopCallback(error:)
            self.websocketConnection!.stateUpdateHandler = stateDidChange(to:)

            // setupReceive
            self.setupReceive()

            print("\(self.name): Websocket connection starting... ")
            self.websocketConnection!.start(queue: self.queue)
            
        case .failed:
            print("\(name): Service connection failed.")
            break
        case .cancelled:
            print("\(name): Service connection cancelled.")
            break
        case .setup, .waiting, .preparing:
            break
        @unknown default:
            break
        }
    }



    // =================================================

    func websocketEndpoint() -> NWEndpoint? {

        var wsHost: String? = nil
        var wsPort: String? = nil
        
        let remoteEndpoint = self.serviceConnection?.currentPath?.remoteEndpoint
        
        if case let .hostPort(host: host, port: port) = remoteEndpoint {
            if case let .name(hostName, _) = host {
                print("\(self.name): Resolved to hostname \(hostName):\(port).")
                wsHost = hostName
                wsPort = String(port.rawValue)
            }
            if case let .ipv4(ipWithInterface) = host {
                // 192.168.7.248%en0
                let str: String = ipWithInterface.debugDescription
                let ip = str.components(separatedBy: "%")[0]
                print("\(self.name): Resolved to IP \(ip):\(port).")

                wsHost = ip
                wsPort = String(port.rawValue)
            }

        } else {
            print("\(self.name): Failed to resolve.")
            return nil
        }

        let websocketURLString = "ws://\(wsHost!):\(wsPort!)/"
        print("\(self.name): websocketURLString: \(websocketURLString)")

        if let websocketURL = URL(string: websocketURLString) {
            return NWEndpoint.url(websocketURL)
        }
        else {
            print("\(self.name): Failed to create URL from \(websocketURLString)")
            return nil
        }

    }
    // =================================================

    
    func stop() {
        print("\(self.name): Client stopping...")
        stop(error: nil)
    }
    
    func send(data: Data) {

        // https://github.com/MichaelNeas/perpetual-learning/blob/master/ios-sockets/SwiftWebSockets/SwiftWebSockets/Networking/NWWebSocket.swift
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "textContext", metadata: [metadata])

        self.websocketConnection!.send(content: data, contentContext: context, completion: .contentProcessed( { error in
            if let error = error {
                self.connectionDidFail(error: error)
                return
            }
//            print("\(self.name): Connection did send, data: \(String(describing: String(data: data, encoding: .utf8)))")
        }))
    }

    private func stateDidChange(to state: NWConnection.State) {
        self.delegate?.connectionStateHasChanged(self.name, state)
    }

    func didStopCallback(error: Error?) {
        if error == nil {
            // exit(EXIT_SUCCESS)
        } else {
            // exit(EXIT_FAILURE)
        }
    }
    
    func connectionDidFail(error: Error) {
        print("\(self.name): Connection did fail, error: \(error)")
        self.delegate?.connectionStateHasChanged(self.name, .cancelled)
        self.stop(error: error)
    }
    
    func connectionDidEnd() {
        print("\(self.name): Connection did end")
        self.delegate?.connectionStateHasChanged(self.name, .cancelled)
        self.stop(error: nil)
    }
    
    private func stop(error: Error?) {
        self.websocketConnection!.stateUpdateHandler = nil
        self.websocketConnection!.cancel()
        if let didStopCallback = self.didStopCallback {
            self.didStopCallback = nil
            didStopCallback(error)
        }
    }
    
    func isConnected() -> Bool {
        if self.websocketConnection == nil { return false }
        return self.websocketConnection!.state == .ready
    }
    
    
    // =================================================
    
    
    func enablePreviews() {
        let json: JSON = [ "newSwitchVector": [ "device": "Imager Agent", "name": "CCD_PREVIEW", "items": [ [ "name": "ENABLED", "value": true ]  ]  ] ]
        self.send(data: json.rawString()!.data(using: .ascii)!)
    }

    func hello() {
        let json: JSON = [ "getProperties": [ "version": 512 ] ]
        self.send(data: json.rawString()!.data(using: .ascii)!)
    }

    func mountPark() {
        let json: JSON = [ "newSwitchVector": [ "device": "Mount Agent", "name": "MOUNT_PARK", "items": [ [ "name": "PARKED", "value": true ] ] ] ]
        self.send(data: json.rawString()!.data(using: .ascii)!)
    }
    func imagerDisableCooler() {
        let json: JSON = [ "newSwitchVector": [ "device": "Imager Agent", "name": "CCD_COOLER", "items": [ [ "name": "OFF", "value": true ] ] ] ]
        self.send(data: json.rawString()!.data(using: .ascii)!)
    }

}

protocol IndigoConnectionDelegate {
    func connectionStateHasChanged(_ name: String, _ state: NWConnection.State)
    func receiveMessage(data: Data?, context: NWConnection.ContentContext?, isComplete: Bool, error: NWError?)
}

