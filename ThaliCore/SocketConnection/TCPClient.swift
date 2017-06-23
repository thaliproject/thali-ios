//
//  Thali CordovaPlugin
//  TCPClient.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

class TCPClient: NSObject {

  // MARK: - Private state
  fileprivate let socketQueue = DispatchQueue(
                                            label: "org.thaliproject.GCDAsyncSocket.delegateQueue",
                                            attributes: DispatchQueue.Attributes.concurrent)
  fileprivate var activeConnections: Atomic<[GCDAsyncSocket]> = Atomic([])
  fileprivate var didReadDataHandler: ((GCDAsyncSocket, Data) -> Void)
  fileprivate var didSocketDisconnectHandler: ((GCDAsyncSocket) -> Void)
  fileprivate var disconnecting = false

  // MARK: - Public methods
  required init(didReadData: @escaping (GCDAsyncSocket, Data) -> Void,
                didDisconnect: @escaping (GCDAsyncSocket) -> Void) {
    didReadDataHandler = didReadData
    didSocketDisconnectHandler = didDisconnect
    super.init()
  }

  deinit {
    print("[ThaliCore] TCPClient.\(#function)")
  }

  func connectToLocalhost(onPort port: UInt16) ->
                         (socket: GCDAsyncSocket?, error: ThaliCoreError?) {
    print("[ThaliCore] TCPClient.\(#function)")
    do {
      let socket = GCDAsyncSocket()
      socket.autoDisconnectOnClosedReadStream = false
      socket.delegate = self
      socket.delegateQueue = socketQueue
      try socket.connect(toHost: "127.0.0.1", onPort: port)
      return(socket, nil)
    } catch _ {
      return(nil, ThaliCoreError.connectionFailed)
    }
  }

  func disconnectClientsFromLocalhost() {
    print("[ThaliCore] TCPClient.\(#function)")
    self.disconnecting = true
    activeConnections.modify {
      $0.forEach {
        $0.disconnect()
      }
      $0.removeAll()
    }
  }
}

// MARK: - GCDAsyncSocketDelegate - Handling socket events
extension TCPClient: GCDAsyncSocketDelegate {

  func socket(_ socket: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
    activeConnections.modify { $0.append(socket) }
    socket.readData(withTimeout: -1, tag: 0)
  }

  func socketDidDisconnect(_ socket: GCDAsyncSocket, withError err: Error?) {
    print("[ThaliCore] TCPClient.\(#function) disconnecting:\(self.disconnecting) " +
          "socket error:\(err)")
    if self.disconnecting == false {
      activeConnections.modify {
        if let indexOfDisconnectedSocket = $0.index(of: socket) {
          $0.remove(at: indexOfDisconnectedSocket)
          print("[ThaliCore] TCPClient.\(#function) client disconnected")
        }
      }

      didSocketDisconnectHandler(socket)
    }
  }

  func socket(_ socket: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
    socket.readData(withTimeout: -1, tag: 0)
  }

  func socket(_ socket: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
    socket.readData(withTimeout: -1, tag: 0)
    didReadDataHandler(socket, data)
  }
}
