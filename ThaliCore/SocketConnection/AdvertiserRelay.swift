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
  fileprivate var nonTCPsession: Session!
  fileprivate var virtualSockets: Atomic<[GCDAsyncSocket: VirtualSocket]>
  fileprivate var disconnecting: Atomic<Bool>

  // MARK: - Initialization
  init(with session: Session, on port: UInt16) {
    print("[ThaliCore] AdvertiserRelay.\(#function)")
    self.nonTCPsession = session
    self.clientPort = port
    self.virtualSockets = Atomic([:])
    self.disconnecting = Atomic(false)
    self.nonTCPsession.didReceiveInputStreamHandler = sessionDidReceiveInputStreamHandler
    self.tcpClient = TCPClient(didReadData: didReadDataHandler,
                               didDisconnect: didSocketDisconnectHandler)
  }

  deinit {
    print("[ThaliCore] AdvertiserRelay.\(#function)")
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
    self.tcpClient = nil

    virtualSockets.modify {
      $0.forEach {
        $0.key.disconnect()
        $0.value.closeStreams()
      }
      $0.removeAll()
    }

    self.disconnectNonTCPSession()
  }

  func disconnectNonTCPSession() {
    print("[ThaliCore] AdvertiserRelay.\(#function)")
    self.nonTCPsession.disconnect()
    self.nonTCPsession.didChangeStateHandler = nil
    self.nonTCPsession.didReceiveInputStreamHandler = nil
    self.nonTCPsession = nil
  }

  // MARK: - Private handlers

  // Called by VirtualSocket.readDataFromInputStream()
  fileprivate func didReadDataFromStreamHandler(_ virtualSocket: VirtualSocket, data: Data) {
    let socket = virtualSockets.value.key(for: virtualSocket)
    guard socket != nil else {
      virtualSocket.closeStreams()
      return
    }

    let noTimeout: TimeInterval = -1
    let defaultDataTag = 0
    socket?.write(data, withTimeout: noTimeout, tag: defaultDataTag)
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

    guard tcpClient != nil else {
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
    virtualSocket.didOpenVirtualSocketStreamsHandler = self.didOpenVirtualSocketStreamsHandler
    virtualSocket.didCloseVirtualSocketStreamsHandler = self.didCloseVirtualSocketStreamsHandler

    self.virtualSockets.modify {
      $0[socket] = virtualSocket
    }
    virtualSocket.openStreams()
  }

  fileprivate func didOpenVirtualSocketStreamsHandler(_ virtualSocket: VirtualSocket) { }

  // Called by VirtualSocket.closeStreams()
  fileprivate func didCloseVirtualSocketStreamsHandler(_ virtualSocket: VirtualSocket) {
    print("[ThaliCore] AdvertiserRelay.\(#function) disconnecting:\(disconnecting.value)")

    virtualSocket.didCloseVirtualSocketStreamsHandler = nil

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
    var virtualSocket: VirtualSocket?
    self.virtualSockets.withValue {
      virtualSocket = $0[socket]
    }
    virtualSocket?.writeDataToOutputStream(data)
  }

  // Called by TCPClient.socketDidDisconnect()
  fileprivate func didSocketDisconnectHandler(_ socket: GCDAsyncSocket) {
    print("[ThaliCore] AdvertiserRelay.\(#function) disconnecting:\(disconnecting.value)")

    guard self.disconnecting.value == false else {
      return
    }

    self.disconnectNonTCPSession()

    var virtualSocket: VirtualSocket!
    self.virtualSockets.withValue {
      virtualSocket = $0[socket]
    }

    guard virtualSocket != nil else {
      return
    }

    self.virtualSockets.modify {
      if let socket = $0.key(for: virtualSocket) {
        $0.removeValue(forKey: socket)
      }
    }

    virtualSocket.closeStreams()
  }
}
