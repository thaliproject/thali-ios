//
//  Thali CordovaPlugin
//  AdvertiserRelay.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

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
    self.disconnecting.modify { disconnecting in
      if disconnecting == false {
        disconnecting = true
        proceed = true
      }
    }

    guard proceed else {
      return
    }

    self.tcpClient.disconnectClientsFromLocalhost()
    self.tcpClient = nil

    virtualSockets.modify { virtualSockets in
      virtualSockets.forEach { virtualSocket in
        virtualSocket.key.disconnect()
        virtualSocket.value.closeStreams()
      }
      virtualSockets.removeAll()
    }

    self.disconnectNonTCPSession()
  }

  func disconnectNonTCPSession() {
    print("[ThaliCore] AdvertiserRelay.\(#function)")
    self.nonTCPsession?.disconnect()
    self.nonTCPsession?.didChangeStateHandler = nil
    self.nonTCPsession?.didReceiveInputStreamHandler = nil
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

    let outputStream = self.nonTCPsession.startOutputStream(with: inputStreamName)
    guard outputStream != nil else {
      // proper error handling (todo)
      print("[ThaliCore] AdvertiserRelay: startOutputStream() failed)")
      return
    }

    let virtualSocket = VirtualSocket(inputStream: inputStream, outputStream: outputStream!)

    guard tcpClient != nil else {
      // proper error handling (todo)
      print("[ThaliCore] AdvertiserRelay: tcpClient is nil)")
      return
    }

    let socket = self.tcpClient.connectToLocalhost(onPort: self.clientPort)
    guard socket != nil else {
      // proper error handling (todo)
      print("[ThaliCore] AdvertiserRelay: connectToLocalhost() failed)")
      return
    }

    virtualSocket.didReadDataFromStreamHandler = self.didReadDataFromStreamHandler
    virtualSocket.didOpenVirtualSocketStreamsHandler = self.didOpenVirtualSocketStreamsHandler
    virtualSocket.didCloseVirtualSocketStreamsHandler = self.didCloseVirtualSocketStreamsHandler

    self.virtualSockets.modify { virtualSockets in
      virtualSockets[socket!] = virtualSocket
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

    self.virtualSockets.modify { virtualSockets in
      if let socket = virtualSockets.key(for: virtualSocket) {
        socket.disconnect()
        virtualSockets.removeValue(forKey: socket)
      }
    }
  }

  // Called by TCPClient
  fileprivate func didReadDataHandler(_ socket: GCDAsyncSocket, data: Data) {
    var virtualSocket: VirtualSocket?
    self.virtualSockets.withValue { virtualSockets in
      virtualSocket = virtualSockets[socket]
    }
    virtualSocket?.writeDataToOutputStream(data)
  }

  // Called by TCPClient.socketDidDisconnect()
  fileprivate func didSocketDisconnectHandler(_ socket: GCDAsyncSocket) {
    print("[ThaliCore] AdvertiserRelay.\(#function) disconnecting:\(disconnecting.value)")

    guard self.disconnecting.value == false else {
      return
    }

    var virtualSocket: VirtualSocket!
    self.virtualSockets.withValue { virtualSockets in
      virtualSocket = virtualSockets[socket]
    }

    guard virtualSocket != nil else {
      return
    }

    self.virtualSockets.modify { virtualSockets in
      if let socket = virtualSockets.key(for: virtualSocket) {
        virtualSockets.removeValue(forKey: socket)
        print("[ThaliCore] AdvertiserRelay.\(#function) removed virtual socket " +
              "vsID:\(virtualSocket.vsID)")
      }
    }

    virtualSocket.closeStreams()
  }
}
