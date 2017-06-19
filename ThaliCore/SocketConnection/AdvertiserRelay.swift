//
//  Thali CordovaPlugin
//  AdvertiserRelay.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

// MARK: - Methods that available for Relay<AdvertiserVirtualSocketBuilder>
final class AdvertiserRelay {

  // MARK: - Internal state
  internal var virtualSocketsAmount: Int {
    return virtualSockets.value.count
  }
  internal fileprivate(set) var clientPort: UInt16

  // MARK: - Private state
  fileprivate var tcpClient: TCPClient!
  fileprivate var nonTCPsession: Session
  fileprivate var virtualSockets: Atomic<[GCDAsyncSocket: VirtualSocket]>
  fileprivate var disconnecting: Atomic<Bool>

  // MARK: - Initialization
  init(with session: Session, on port: UInt16) {
    nonTCPsession = session
    clientPort = port
    virtualSockets = Atomic([:])
    disconnecting = Atomic(false)
    nonTCPsession.didReceiveInputStreamHandler = sessionDidReceiveInputStreamHandler
    tcpClient = TCPClient(with: didReadDataHandler, didDisconnect: didDisconnectHandler)
  }

  // MARK: - Internal methods
  func closeRelay() {
    print("[ThaliCore] AdvertiserRelay.\(#function)")
    var proceed = false
    self.disconnecting.modify {
      if $0 == false {
        $0 = true
        proceed = true
      }
    }

    guard proceed else {
      return
    }

    tcpClient.disconnectClientsFromLocalhost()

    for (_, virtualSocket) in self.virtualSockets.value.enumerated() {
      virtualSocket.value.closeStreams()
    }

    self.virtualSockets.modify {
      $0.removeAll()
    }

    nonTCPsession.disconnect()
  }

  // MARK: - Private handlers

  // Called by VirtualSocket.readDataFromInputStream()
  fileprivate func didReadDataFromStreamHandler(_ virtualSocket: VirtualSocket, data: Data) {
    guard let socket = virtualSockets.value.key(for: virtualSocket) else {
      virtualSocket.closeStreams()
      return
    }

    let noTimeout: TimeInterval = -1
    let defaultDataTag = 0
    socket.write(data, withTimeout: noTimeout, tag: defaultDataTag)
  }

  fileprivate func sessionDidReceiveInputStreamHandler(_ inputStream: InputStream,
                                                       inputStreamName: String) {
    createVirtualSocket(with: inputStream,
                        inputStreamName: inputStreamName) { [weak self] virtualSocket, error in
      guard let strongSelf = self else { return }

      guard error == nil else {
        return
      }

      guard let virtualSocket = virtualSocket else {
        return
      }

      strongSelf.tcpClient.connectToLocalhost(onPort: strongSelf.clientPort,
                                              completion: { socket, _, _ in
        guard let socket = socket else {
          return
        }

        virtualSocket.didOpenVirtualSocketHandler = strongSelf.didOpenVirtualSocketHandler
        virtualSocket.didReadDataFromStreamHandler = strongSelf.didReadDataFromStreamHandler
        virtualSocket.didCloseVirtualSocketHandler = strongSelf.didCloseVirtualSocketHandler

        strongSelf.virtualSockets.modify {
          $0[socket] = virtualSocket
        }

        virtualSocket.openStreams()
      })
    }
  }

  fileprivate func createVirtualSocket(with inputStream: InputStream,
                                       inputStreamName: String,
                                       completion: @escaping ((VirtualSocket?, Error?) -> Void)) {
    print("[ThaliCore] AdvertiserRelay.\(#function)")
    let virtualSockBuilder = AdvertiserVirtualSocketBuilder(
                                                    with: nonTCPsession) { virtualSocket, error in
      completion(virtualSocket, error)
    }

    virtualSockBuilder.createVirtualSocket(with: inputStream, inputStreamName: inputStreamName)
  }

  fileprivate func didOpenVirtualSocketHandler(_ virtualSocket: VirtualSocket) { }

  // Called by VirtualSocket.closeStreams()
  fileprivate func didCloseVirtualSocketHandler(_ virtualSocket: VirtualSocket) {
    print("[ThaliCore] AdvertiserRelay.\(#function)")

    guard self.disconnecting.value == false else {
      return
    }
    virtualSockets.modify {
      if let socket = $0.key(for: virtualSocket) {
        socket.disconnect()
        $0.removeValue(forKey: socket)
      }
    }
  }

  // Called by TCPClient
  fileprivate func didReadDataHandler(_ socket: GCDAsyncSocket, data: Data) {
    virtualSockets.withValue {
      let virtualSocket = $0[socket]
      virtualSocket?.writeDataToOutputStream(data)
    }
  }

  // Called by TCPClient.socketDidDisconnect()
  fileprivate func didDisconnectHandler(_ socket: GCDAsyncSocket) {
    print("[ThaliCore] AdvertiserRelay.\(#function)")

    guard self.disconnecting.value == false else {
      return
    }

    var virtualSocket: VirtualSocket?
    virtualSockets.withValue {
      virtualSocket = $0[socket]
    }
    virtualSocket?.closeStreams()
  }
}
