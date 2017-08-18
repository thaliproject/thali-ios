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
  fileprivate var didReadDataHandler: ((GCDAsyncSocket, Data) -> Void)!
  fileprivate var didSocketDisconnectHandler: ((GCDAsyncSocket) -> Void)!
  fileprivate var disconnecting = false

  // MARK: - Public methods
  required init(didReadData: @escaping (GCDAsyncSocket, Data) -> Void,
                didDisconnect: @escaping (GCDAsyncSocket) -> Void) {
    print("[ThaliCore] TCPClient.\(#function)")
    didReadDataHandler = didReadData
    didSocketDisconnectHandler = didDisconnect
    super.init()
  }

  deinit {
    print("[ThaliCore] TCPClient.\(#function)")
  }

  func connectToLocalhost(onPort port: UInt16) -> GCDAsyncSocket? {
    print("[ThaliCore] TCPClient.\(#function)")
    do {
      let socket = GCDAsyncSocket()
      socket.autoDisconnectOnClosedReadStream = true
      socket.delegate = self
      socket.delegateQueue = socketQueue
      try socket.connect(toHost: "127.0.0.1", onPort: port)
      return socket
    } catch let error {
      print("[ThaliCore] TCPClient.\(#function) failed, error:\(error)")
      return nil
    }
  }

  func disconnectClientsFromLocalhost() {
    print("[ThaliCore] TCPClient.\(#function)")
    self.disconnecting = true
    activeConnections.modify { activeConnections in
      activeConnections.forEach { activeConnection in
        activeConnection.disconnect()
      }
      activeConnections.removeAll()
    }
    didReadDataHandler = nil
    didSocketDisconnectHandler = nil
  }
}

// MARK: - GCDAsyncSocketDelegate - Handling socket events
extension TCPClient: GCDAsyncSocketDelegate {

  func socket(_ socket: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
    print("[ThaliCore] TCPClient: didConnectToHost, active connections count: " +
          "\(activeConnections.value.count)")
    activeConnections.modify { activeConnections in
      activeConnections.append(socket)
    }
    socket.readData(withTimeout: -1, tag: 0)
  }

  func socketDidDisconnect(_ socket: GCDAsyncSocket, withError err: Error?) {
    print("[ThaliCore] TCPClient.\(#function) disconnecting:\(self.disconnecting) " +
          "socket error:\(err)")

    guard self.disconnecting == false else {
      return
    }

    activeConnections.modify { activeConnections in
      if let indexOfDisconnectedSocket = activeConnections.index(of: socket) {
        activeConnections.remove(at: indexOfDisconnectedSocket)
        print("[ThaliCore] TCPClient.\(#function) client disconnected")
      }
    }

    didSocketDisconnectHandler(socket)
  }

  func socket(_ socket: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
    socket.readData(withTimeout: -1, tag: 0)
  }

  func socket(_ socket: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {

    guard self.disconnecting == false else {
      return
    }

    socket.readData(withTimeout: -1, tag: 0)
    didReadDataHandler(socket, data)
  }
}
