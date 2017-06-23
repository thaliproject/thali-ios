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
    self.nonTCPsession = session
    self.clientPort = port
    self.virtualSockets = Atomic([:])
    self.disconnecting = Atomic(false)
    self.nonTCPsession.didReceiveInputStreamHandler = sessionDidReceiveInputStreamHandler
    self.tcpClient = TCPClient(didReadData: didReadDataHandler,
                               didDisconnect: didSocketDisconnectHandler)
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

    self.tcpClient.disconnectClientsFromLocalhost()

    for (_, virtualSocket) in self.virtualSockets.value.enumerated() {
      virtualSocket.value.closeStreams()
    }

    self.virtualSockets.modify {
      $0.removeAll()
    }

    self.nonTCPsession.disconnect()
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

    let virtualSocketBuilder = AdvertiserVirtualSocketBuilder(nonTCPsession: nonTCPsession)
    let createVSResult = virtualSocketBuilder.createVirtualSocket(inputStream: inputStream,
                                                                  inputStreamName: inputStreamName)

    guard createVSResult.error == nil else {
      // proper error handling (todo)
      print("[ThaliCore] createVirtualSocket failed: \(String(describing: createVSResult.error))")
      return
    }

    guard let virtualSocket = createVSResult.virtualSocket else {
      // proper error handling (todo)
      print("[ThaliCore] createVirtualSocket failed: returned VirtualSocket is nil)")
      return
    }

    let connectResult = self.tcpClient.connectToLocalhost(onPort: self.clientPort)

    guard connectResult.error == nil else {
      // proper error handling (todo)
      print("[ThaliCore] connectToLocalhost failed: \(String(describing: connectResult.error))")
      return
    }

    guard let socket = connectResult.socket else {
      // proper error handling (todo)
      print("[ThaliCore] connectToLocalhost failed: returned socket is nil)")
      return
    }

    virtualSocket.didReadDataFromStreamHandler = self.didReadDataFromStreamHandler
    virtualSocket.didOpenVirtualSocketHandler = self.didOpenVirtualSocketHandler
    virtualSocket.didCloseVirtualSocketStreamsHandler = self.didCloseVirtualSocketStreamsHandler

    self.virtualSockets.modify {
      $0[socket] = virtualSocket
    }
    virtualSocket.openStreams()
  }

  fileprivate func didOpenVirtualSocketHandler(_ virtualSocket: VirtualSocket) { }

  // Called by VirtualSocket.closeStreams()
  fileprivate func didCloseVirtualSocketStreamsHandler(_ virtualSocket: VirtualSocket) {
    print("[ThaliCore] AdvertiserRelay.\(#function)")

    guard self.disconnecting.value == false else {
      return
    }

    self.virtualSockets.modify {
      if let socket = $0.key(for: virtualSocket) {
        socket.disconnect()
        $0.removeValue(forKey: socket)
      }
    }
  }

  // Called by TCPClient
  fileprivate func didReadDataHandler(_ socket: GCDAsyncSocket, data: Data) {
    self.virtualSockets.withValue {
      let virtualSocket = $0[socket]
      virtualSocket?.writeDataToOutputStream(data)
    }
  }

  // Called by TCPClient.socketDidDisconnect()
  fileprivate func didSocketDisconnectHandler(_ socket: GCDAsyncSocket) {
    print("[ThaliCore] AdvertiserRelay.\(#function)")

    guard self.disconnecting.value == false else {
      return
    }

    var virtualSocket: VirtualSocket?
    self.virtualSockets.withValue {
      virtualSocket = $0[socket]
    }
    virtualSocket?.closeStreams()
  }
}
