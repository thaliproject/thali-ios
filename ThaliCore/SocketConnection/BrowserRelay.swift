//
//  Thali CordovaPlugin
//  BrowserRelay.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

final class BrowserRelay {

  // MARK: - Public state
  public enum RelayState {

    case connecting, connected, disconnecting

  }
  public var state: RelayState
  public fileprivate(set) var generation: Int

  // MARK: - Internal state
  internal var virtualSocketsAmount: Int {
    return virtualSockets.value.count
  }
  internal var listenerPort: UInt16 {
    return tcpListener.listenerPort
  }
  internal var nonTCPsession: Session!

  // MARK: - Private state
  fileprivate var tcpListener: TCPListener!
  fileprivate var virtualSocketBuilders: Atomic<[String: BrowserVirtualSocketBuilder]>
  fileprivate var virtualSockets: Atomic<[GCDAsyncSocket: VirtualSocket]>
  fileprivate let createVirtualSocketTimeout: TimeInterval

  static let mutex = PosixThreadMutex()

  // MARK: - Initialization
  init(session: Session, generation: Int, createVirtualSocketTimeout: TimeInterval) {
    print("[ThaliCore] BrowserRelay.\(#function)")
    self.state = RelayState.connecting
    self.nonTCPsession = session
    self.generation = generation
    self.createVirtualSocketTimeout = createVirtualSocketTimeout
    self.virtualSockets = Atomic([:])
    self.virtualSocketBuilders = Atomic([:])
    nonTCPsession.didReceiveInputStreamHandler = sessionDidReceiveInputStreamHandler
    tcpListener = TCPListener(with: didReadDataFromSocketHandler,
                              socketDisconnected: didSocketDisconnectHandler,
                              stoppedListening: didStopListeningHandler)
  }

  deinit {
    print("[ThaliCore] BrowserRelay.\(#function)")
  }

  // MARK: - Internal methods
  func openRelay(with completion: @escaping (_ port: UInt16?, _ error: Error?) -> Void) {
    print("[ThaliCore] BrowserRelay.\(#function)")
    let anyAvailablePort: UInt16 = 0
    tcpListener.startListeningForConnections(
                                   on: anyAvailablePort,
                                   connectionAccepted: didAcceptConnectionHandler) { port, error in
      completion(port, error)
    }
    self.state = RelayState.connected
  }

  func closeRelay() {
    print("[ThaliCore] BrowserRelay.\(#function) state:\(self.state)")
    var proceed = false
    BrowserRelay.mutex.lock()
    if self.state != RelayState.disconnecting {
      self.state = RelayState.disconnecting
      proceed = true
    }
    BrowserRelay.mutex.unlock()

    guard proceed else {
      return
    }

    tcpListener.stopListeningForConnectionsAndDisconnectClients()
    tcpListener = nil

    virtualSockets.modify { virtualSockets in
      virtualSockets.forEach { virtualSocket in
        virtualSocket.key.disconnect()
        virtualSocket.value.closeStreams()
      }
    }

    self.virtualSockets.modify { virtualSockets in
      virtualSockets.removeAll()
    }

    self.virtualSocketBuilders.modify { virtualSocketBuilders in
      virtualSocketBuilders.removeAll()
    }

    self.disconnectNonTCPSession()
  }

  func disconnectNonTCPSession() {
    self.nonTCPsession?.disconnect()
    self.nonTCPsession = nil
  }

  // MARK: - Private handlers
  fileprivate func sessionDidReceiveInputStreamHandler(_ inputStream: InputStream,
                                                       inputStreamName: String) {
    if let builder = virtualSocketBuilders.value[inputStreamName] {
      builder.completeVirtualSocket(inputStream: inputStream)
    } else {
      inputStream.close()
    }
  }

  fileprivate func didReadDataFromStreamHandler(on virtualSocket: VirtualSocket, data: Data) {
    virtualSockets.withValue { virtualSockets in
      if let socket = virtualSockets.key(for: virtualSocket) {
        let noTimeout: TimeInterval = -1
        let defaultDataTag = 0
        socket.write(data, withTimeout: noTimeout, tag: defaultDataTag)
      }
    }
  }

  fileprivate func didAcceptConnectionHandler(_ socket: GCDAsyncSocket) {
    createVirtualSocket { [weak self] virtualSocket, error in
      guard let strongSelf = self else {
        return
      }

      guard error == nil else {
        socket.disconnect()
        return
      }

      guard let virtualSocket = virtualSocket else {
        socket.disconnect()
        return
      }

      virtualSocket.didOpenVirtualSocketStreamsHandler =
                                            strongSelf.didOpenVirtualSocketStreamsHandler
      virtualSocket.didReadDataFromStreamHandler = strongSelf.didReadDataFromStreamHandler
      virtualSocket.didCloseVirtualSocketStreamsHandler =
                                            strongSelf.didCloseVirtualSocketStreamsHandler

      strongSelf.virtualSockets.modify { virtualSockets in
        virtualSockets[socket] = virtualSocket
      }

      virtualSocket.openStreams()
    }
  }

  fileprivate func didReadDataFromSocketHandler(_ socket: GCDAsyncSocket, data: Data) {
    guard let virtualSocket = virtualSockets.value[socket] else {
      socket.disconnect()
      return
    }

    virtualSocket.writeDataToOutputStream(data)
  }

  // Called by VirtualSocket.closeStreams()
  fileprivate func didCloseVirtualSocketStreamsHandler(_ virtualSocket: VirtualSocket) {
    print("[ThaliCore] BrowserRelay.\(#function) state:\(String(describing: self.state))")
    guard self.state != RelayState.disconnecting else {
      return
    }

    virtualSockets.modify { virtualSockets in
      if let socket = virtualSockets.key(for: virtualSocket) {
        socket.disconnect()
        virtualSockets.removeValue(forKey: socket)
      }
    }
  }

  // Called by TCPListener
  fileprivate func didSocketDisconnectHandler(_ socket: GCDAsyncSocket) {
    print("[ThaliCore] BrowserRelay.\(#function)")
    var virtualSocket: VirtualSocket!
    self.virtualSockets.withValue { virtualSockets in
      virtualSocket = virtualSockets[socket]
    }

    guard virtualSocket != nil else {
      return
    }

    // We remove the virtual socket here because if the streams are not opened yet
    // calling closeStreams will not trigger didCloseVirtualSocketStreamsHandler
    // causing a virtual socket leak
    virtualSockets.modify { virtualSockets in
      if let socket = virtualSockets.key(for: virtualSocket) {
        virtualSockets.removeValue(forKey: socket)
        print("[ThaliCore] BrowserRelay.\(#function) socket removed, count:\(virtualSockets.count)")
      }
    }

    virtualSocket.closeStreams()
  }

  // Called by TCPListener
  fileprivate func didStopListeningHandler() {

    guard self.state != RelayState.disconnecting else {
      return
    }

    disconnectNonTCPSession()
  }

  // This is called after both the input and output have been opened
  fileprivate func didOpenVirtualSocketStreamsHandler(_ virtualSocket: VirtualSocket) {
    print("[ThaliCore] BrowserRelay.\(#function)")
    guard let socket = virtualSockets.value.key(for: virtualSocket) else {
      virtualSocket.closeStreams()
      return
    }
    socket.readData(withTimeout: -1, tag: 1)
  }

  // MARK: - Private methods
  fileprivate func createVirtualSocket(
                      with completion: @escaping ((VirtualSocket?, Error?) -> Void)) {
    print("[ThaliCore] BrowserRelay.\(#function)")

    guard self.nonTCPsession != nil else {
      completion(nil, ThaliCoreError.sessionDisconnected)
      return
    }

    let newStreamName = UUID().uuidString
    let virtualSocketBuilder = BrowserVirtualSocketBuilder(
      nonTCPsession: nonTCPsession,
      streamName: newStreamName,
      streamReceivedBackTimeout: createVirtualSocketTimeout)

    virtualSocketBuilders.modify { virtualSocketBuilders in
      virtualSocketBuilders[virtualSocketBuilder.streamName] = virtualSocketBuilder
    }

    virtualSocketBuilder.startBuilding { virtualSocket, error in
      _ = self.virtualSocketBuilders.modify { virtualSocketBuilders in
        virtualSocketBuilders.removeValue(forKey: newStreamName)
      }

      completion(virtualSocket, error)
    }
  }
}
