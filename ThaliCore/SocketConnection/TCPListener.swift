//
//  Thali CordovaPlugin
//  TCPListener.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

/**
 Provides simple methods that listen for and accept incoming TCP connection requests.
 */
class TCPListener: NSObject {

  // MARK: - Internal state
  internal var listenerPort: UInt16 {
    return self.listeningSocket.localPort
  }

  // MARK: - Private state
  fileprivate let listeningSocket: GCDAsyncSocket
  fileprivate var listening = false

  fileprivate let socketQueue = DispatchQueue(
                                  label: "org.thaliproject.GCDAsyncSocket.delegateQueue",
                                  attributes: DispatchQueue.Attributes.concurrent)
  fileprivate let activeConnections: Atomic<[GCDAsyncSocket]> = Atomic([])

  fileprivate var didAcceptConnectionHandler: ((GCDAsyncSocket) -> Void)?
  fileprivate let didReadDataFromSocketHandler: ((GCDAsyncSocket, Data) -> Void)
  fileprivate let didSocketDisconnectHandler: ((GCDAsyncSocket) -> Void)
  fileprivate let didStopListeningHandler: () -> Void

  // MARK: - Initialization
  required init(with didReadDataFromSocket: @escaping (GCDAsyncSocket, Data) -> Void,
                socketDisconnected: @escaping (GCDAsyncSocket) -> Void,
                stoppedListening: @escaping () -> Void) {
    print("[ThaliCore] TCPListener.\(#function)")
    listeningSocket = GCDAsyncSocket()
    didReadDataFromSocketHandler = didReadDataFromSocket
    didSocketDisconnectHandler = socketDisconnected
    didStopListeningHandler = stoppedListening
    super.init()
    listeningSocket.autoDisconnectOnClosedReadStream = false
    listeningSocket.delegate = self
    listeningSocket.delegateQueue = socketQueue
  }

  deinit {
    print("[ThaliCore] TCPListener.\(#function)")
  }

  // MARK: - Internal methods
  func startListeningForConnections(on port: UInt16,
                                    connectionAccepted: @escaping (GCDAsyncSocket) -> Void,
                                    completion: (_ port: UInt16?, _ error: Error?) -> Void) {
    if !listening {
      do {
        try listeningSocket.accept(onPort: port)
        print("[ThaliCore] TCPListener.\(#function) port:\(port) " +
              "localport:\(listeningSocket.localPort)")
        listening = true
        didAcceptConnectionHandler = connectionAccepted
        completion(listeningSocket.localPort, nil)
      } catch _ {
        listening = false
        completion(0, ThaliCoreError.connectionFailed)
      }
    }
  }

  func stopListeningForConnectionsAndDisconnectClients() {
    if listening {
      print("[ThaliCore] TCPListener.\(#function) port:\(listeningSocket.localPort)")
      listening = false
      listeningSocket.disconnect()
    }
  }
}

// MARK: - GCDAsyncSocketDelegate - Handling socket events
extension TCPListener: GCDAsyncSocketDelegate {

  func socketDidDisconnect(_ socket: GCDAsyncSocket, withError err: Error?) {
    if socket == listeningSocket {
      print("[ThaliCore] TCPListener.\(#function) listening socket error:\(err)")
      didStopListeningHandler()
    } else {
      print("[ThaliCore] TCPListener.\(#function) accepted socket error:\(err)")
      activeConnections.modify {
        if let indexOfDisconnectedSocket = $0.index(of: socket) {
          $0.remove(at: indexOfDisconnectedSocket)
        }
      }
      didSocketDisconnectHandler(socket)
    }
  }

  func socket(_ socket: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
    print("[ThaliCore] TCPListener.\(#function)")
    newSocket.autoDisconnectOnClosedReadStream = false
    activeConnections.modify { $0.append(newSocket) }
    didAcceptConnectionHandler?(newSocket)
  }

  func socket(_ socket: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
    socket.readData(withTimeout: -1, tag: 0)
  }

  func socket(_ socket: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
    didReadDataFromSocketHandler(socket, data)
    socket.readData(withTimeout: -1, tag: 0)
  }
}
