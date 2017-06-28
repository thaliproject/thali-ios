//
//  Thali CordovaPlugin
//  BrowserRelay.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

// MARK: - Methods that available for Relay<BrowserVirtualSocketBuilder>
final class BrowserRelay {

  // MARK: - Public state
  public fileprivate(set) var generation: Int

  // MARK: - Internal state
  internal var virtualSocketsAmount: Int {
    return virtualSockets.value.count
  }
  internal var listenerPort: UInt16 {
    return tcpListener.listenerPort
  }
  internal var nonTCPsession: Session

  // MARK: - Private state
  fileprivate var tcpListener: TCPListener!
  fileprivate var virtualSocketBuilders: Atomic<[String: BrowserVirtualSocketBuilder]>
  fileprivate var virtualSockets: Atomic<[GCDAsyncSocket: VirtualSocket]>
  fileprivate let createVirtualSocketTimeout: TimeInterval
  fileprivate let maxVirtualSocketsCount = 16
  fileprivate var disconnecting: Atomic<Bool>

  // MARK: - Initialization
  init(session: Session, generation: Int, createVirtualSocketTimeout: TimeInterval) {
    print("[ThaliCore] BrowserRelay.\(#function)")
    self.nonTCPsession = session
    self.generation = generation
    self.createVirtualSocketTimeout = createVirtualSocketTimeout
    self.virtualSockets = Atomic([:])
    self.virtualSocketBuilders = Atomic([:])
    self.disconnecting = Atomic(false)
    nonTCPsession.didReceiveInputStreamHandler = sessionDidReceiveInputStreamHandler
    tcpListener = TCPListener(with: didReadDataFromSocketHandler,
                              socketDisconnected: didSocketDisconnectHandler,
                              stoppedListening: didStopListeningHandler)
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
  }

  func closeRelay() {
    print("[ThaliCore] BrowserRelay.\(#function) disconnecting:\(self.disconnecting.value)")
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

    tcpListener.stopListeningForConnectionsAndDisconnectClients()

    for (_, virtualSocket) in self.virtualSockets.value.enumerated() {
      virtualSocket.value.closeStreams()
    }

    self.virtualSockets.modify {
      $0.removeAll()
    }

    self.virtualSocketBuilders.modify {
      $0.removeAll()
    }

    disconnectNonTCPSession()
  }

  func disconnectNonTCPSession() {
    nonTCPsession.disconnect()
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
    virtualSockets.withValue {
      if let socket = $0.key(for: virtualSocket) {
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

      strongSelf.virtualSockets.modify {
        $0[socket] = virtualSocket
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
    print("[ThaliCore] BrowserRelay.\(#function)")
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

  // Called by TCPListener
  fileprivate func didSocketDisconnectHandler(_ socket: GCDAsyncSocket) {
    print("[ThaliCore] BrowserRelay.\(#function)")
    var virtualSocket: VirtualSocket!
    self.virtualSockets.withValue {
      virtualSocket = $0[socket]
    }

    guard virtualSocket != nil else {
      return
    }
    
    // We remove the virtual socket here because if the streams are not opened yet
    // calling closeStreams will not trigger didCloseVirtualSocketStreamsHandler
    // causing a virtual socket leak
    virtualSockets.modify {
      if let socket = $0.key(for: virtualSocket) {
        $0.removeValue(forKey: socket)
      }
    }

    virtualSocket.closeStreams()
  }

  // Called by TCPListener
  fileprivate func didStopListeningHandler() {

    guard self.disconnecting.value == false else {
      return
    }

    self.nonTCPsession.disconnect()
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
    guard virtualSockets.value.count < maxVirtualSocketsCount else {
      print("[ThaliCore] BrowserRelay.\(#function) MAX connections reached")
      completion(nil, ThaliCoreError.maxConnectionsReached)
      return
    }

    let newStreamName = UUID().uuidString
    let virtualSocketBuilder = BrowserVirtualSocketBuilder(
      nonTCPsession: nonTCPsession,
      streamName: newStreamName,
      streamReceivedBackTimeout: createVirtualSocketTimeout)

    virtualSocketBuilders.modify {
      $0[virtualSocketBuilder.streamName] = virtualSocketBuilder
    }

    virtualSocketBuilder.startBuilding { virtualSocket, error in
      _ = self.virtualSocketBuilders.modify {
        $0.removeValue(forKey: newStreamName)
      }

      completion(virtualSocket, error)
    }
  }
}
