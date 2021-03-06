//
//  Thali CordovaPlugin
//  TCPServerMock.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

import CocoaAsyncSocket
import ThaliCore

class TCPServerMock: NSObject {

  fileprivate let tcpListener: GCDAsyncSocket
  fileprivate var activeConnections: Atomic<[GCDAsyncSocket]> = Atomic([])

  static fileprivate let delegateQueueName =
    "org.thaliproject.TCPServerMock.GCDAsyncSocket.delegateQueue"
  fileprivate let delegateQueue = DispatchQueue(
                                    label: delegateQueueName,
                                    attributes: DispatchQueue.Attributes.concurrent
                                  )
  fileprivate var didAcceptConnectionHandler: () -> Void
  fileprivate var didReadDataHandler: (GCDAsyncSocket, Data) -> Void
  fileprivate var didDisconnectHandler: (GCDAsyncSocket) -> Void

  init(didAcceptConnection: @escaping () -> Void,
       didReadData: @escaping (GCDAsyncSocket, Data) -> Void,
       didDisconnect: @escaping (GCDAsyncSocket) -> Void) {
    tcpListener = GCDAsyncSocket()
    didAcceptConnectionHandler = didAcceptConnection
    didReadDataHandler = didReadData
    didDisconnectHandler = didDisconnect
    super.init()
    tcpListener.delegate = self
    tcpListener.delegateQueue = delegateQueue
  }

  /**
   Start listener on localhost.

   - parameters:
     - port:
       TCP port number that listens for incoming connections.

       Default value is 0 which means any available port.

   - returns:
     number of port that listens for connections.

   - throws:
     ThaliCoreError.connectionFailed if can't start listener on given port
   */
  func startListening(on port: UInt16 = 0) throws -> UInt16 {
    do {
      try tcpListener.accept(onPort: port)
      return tcpListener.localPort
    } catch _ {
      throw ThaliCoreError.connectionFailed
    }
  }

  /***/
  func disconnectAllClients() {
    activeConnections.modify { activeConnections in
      activeConnections.forEach { activeConnection in
        activeConnection.disconnect()
      }
      activeConnections.removeAll()
    }
  }

  /***/
  func sendRandomMessage(length: Int) {
    guard length > 0 else { return }

    let randomMessage = String.random(length: length)
    let messageData = randomMessage.data(using: String.Encoding.utf8)

    activeConnections.withValue { activeConnections in
      activeConnections.forEach { activeConnection in
        activeConnection.write(messageData!, withTimeout: -1, tag: 0)
      }
    }
  }

  /***/
  func send(_ message: String) {
    guard let messageData = message.data(using: String.Encoding.utf8) else { return }

    while activeConnections.value.count == 0 {}
    activeConnections.withValue { activeConnections in
      activeConnections.forEach { activeConnection in
        activeConnection.write(messageData, withTimeout: -1, tag: 0)
      }
    }
  }
}

// MARK: GCDAsyncSocketDelegate events
extension TCPServerMock: GCDAsyncSocketDelegate {

  func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
    activeConnections.modify { activeConnections in
      activeConnections.append(newSocket)
      newSocket.readData(to: GCDAsyncSocket.crlfData(), withTimeout: -1, tag: 0)
    }

    didAcceptConnectionHandler()
  }

  func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
    activeConnections.modify { activeConnections in
      if let indexOfDisconnectedSocket = activeConnections.index(of: sock) {
        activeConnections.remove(at: indexOfDisconnectedSocket)
      }
    }
    didDisconnectHandler(sock)
  }

  func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
    didReadDataHandler(sock, data)
  }

  func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {}
  func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {}
  func socketDidCloseReadStream(_ sock: GCDAsyncSocket) {}
}
