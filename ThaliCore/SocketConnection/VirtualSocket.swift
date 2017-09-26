//
//  Thali CordovaPlugin
//  VirtualSocket.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

/**
 `VirtualSocket` class manages non-TCP virtual socket.

 Non-TCP virtual socket is a combination of the non-TCP output and input streams
 */
class VirtualSocket: NSObject {

  // MARK: - Internal state
  internal fileprivate(set) var streamsOpened: Bool
  internal var didOpenVirtualSocketStreamsHandler: ((VirtualSocket) -> Void)?
  internal var didReadDataFromStreamHandler: ((VirtualSocket, Data) -> Void)?
  internal var didCloseVirtualSocketStreamsHandler: ((VirtualSocket) -> Void)?

  // MARK: - Private state
  fileprivate var inputStream: InputStream?
  fileprivate var outputStream: OutputStream?

  fileprivate var runLoop: RunLoop?

  fileprivate var inputStreamOpened = false
  fileprivate var outputStreamOpened = false

  let maxReadWriteBufferLength = 4096
  fileprivate var dataQueue: Array<Data> = []
  fileprivate let dataQueueMutex: PosixThreadMutex

  fileprivate let mutex: PosixThreadMutex

  // --- For debugging purpose only ---
  static var idCounter = 0
  static var openSockets: [Int] = []
  static let mutexForID = PosixThreadMutex()
  let vsID: Int
  // ----------------------------------

  // MARK: - Initialize
  init(inputStream: InputStream, outputStream: OutputStream) {
    // For debugging purpose only
    VirtualSocket.mutexForID.lock()
    VirtualSocket.idCounter += 1
    VirtualSocket.openSockets.append(VirtualSocket.idCounter)
    self.vsID = VirtualSocket.idCounter
    print("[ThaliCore] VirtualSocket.\(#function) vsID:\(vsID) \(VirtualSocket.openSockets)")
    VirtualSocket.mutexForID.unlock()

    self.streamsOpened = false
    self.inputStream = inputStream
    self.outputStream = outputStream
    self.mutex = PosixThreadMutex()
    self.dataQueueMutex = PosixThreadMutex()
    super.init()
  }

  deinit {
    // For debugging purpose only
    VirtualSocket.mutexForID.lock()
    if let index = VirtualSocket.openSockets.index(of: self.vsID) {
      VirtualSocket.openSockets.remove(at: index)
    }
    print("[ThaliCore] VirtualSocket.\(#function) vsID:\(vsID) \(VirtualSocket.openSockets)")
    VirtualSocket.mutexForID.unlock()
  }

  // MARK: - Internal methods
  func openStreams() {
    mutex.lock()
    defer { mutex.unlock() }

    guard self.streamsOpened == false else {
      return
    }

    self.streamsOpened = true

    let queue = DispatchQueue.global(qos: .default)
    queue.async(execute: {
      self.runLoop = RunLoop.current

      self.inputStream?.delegate = self
      self.inputStream?.schedule(in: self.runLoop!,
        forMode: RunLoopMode.defaultRunLoopMode)
      self.inputStream?.open()

      self.outputStream?.delegate = self
      self.outputStream?.schedule(in: self.runLoop!,
        forMode: RunLoopMode.defaultRunLoopMode)
      self.outputStream?.open()

      RunLoop.current.run(until: Date.distantFuture)
      print("[ThaliCore] VirtualSocket exited RunLoop vsID:\(self.vsID)")
    })
  }

  func closeStreams() {
    print("[ThaliCore] VirtualSocket.\(#function) vsID:\(vsID)")
    mutex.lock()
    defer {
      mutex.unlock()
      didCloseVirtualSocketStreamsHandler?(self)
    }

    guard self.streamsOpened == true else {
      return
    }

    self.streamsOpened = false

    guard self.runLoop != nil else {
      return
    }

    if inputStreamOpened == true {
      inputStream?.close()
      inputStream?.remove(from: self.runLoop!, forMode: RunLoopMode.defaultRunLoopMode)
      inputStream?.delegate = nil
      inputStreamOpened = false
    }

    if outputStreamOpened == true {
      outputStream?.close()
      outputStream?.remove(from: self.runLoop!, forMode: RunLoopMode.defaultRunLoopMode)
      outputStream?.delegate = nil
      outputStreamOpened = false
    }

    CFRunLoopStop(self.runLoop!.getCFRunLoop())

    self.didOpenVirtualSocketStreamsHandler = nil
    self.didReadDataFromStreamHandler = nil

    inputStream = nil
    outputStream = nil
  }

  // Public method
  func writeDataToOutputStream(_ data: Data) {

    dataQueueMutex.lock()
    dataQueue.append(data)
    dataQueueMutex.unlock()

    writePendingData()
  }

  // Event handler for Stream.Event.hasSpaceAvailable
  func writePendingData() {

    guard let strongOuputStream = self.outputStream else {
      return
    }

    dataQueueMutex.lock()

    if dataQueue.count > 0 {
      print("[ThaliCore] VirtualSocket.\(#function) len: \(dataQueue.first?.count ?? 0)")
      if let strongData = dataQueue.first {
        let dataLength = strongData.count

        // if strongOuputStream.hasSpaceAvailable {
        let bytesWritten = strongData.withUnsafeBytes { bytes in
          strongOuputStream.write(bytes, maxLength: dataLength)
        }

        if bytesWritten == dataLength {
          dataQueue.removeFirst()
        } else if bytesWritten == -1 {
          // closeStreams()
          print("[ThaliCore] VirtualSocket.\(#function) writing:\(dataLength) " +
                "written:\(bytesWritten)")
        } else {
          print("[ThaliCore] VirtualSocket.\(#function) writing:\(dataLength) " +
                "written:\(bytesWritten)")
        }
      }
    }

    dataQueueMutex.unlock()
  }

  // Event handler for Stream.Event.hasBytesAvailable
  fileprivate func readDataFromInputStream() {

    guard let strongInputStream = self.inputStream else {
      return
    }

    var buffer = [UInt8](repeating: 0, count: maxReadWriteBufferLength)

    let bytesReaded = strongInputStream.read(&buffer, maxLength: maxReadWriteBufferLength)
    print("[ThaliCore] VirtualSocket.\(#function) reading: \(bytesReaded)")
    if bytesReaded > 0 {
      let data = Data(bytes: buffer, count: bytesReaded)
      didReadDataFromStreamHandler?(self, data)
    }
  }
}

// MARK: - NSStreamDelegate - Handling stream events
extension VirtualSocket: StreamDelegate {

  // MARK: - Delegate methods
  internal func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
    if aStream == self.inputStream {
      handleEventOnInputStream(eventCode)
    } else if aStream == self.outputStream {
      handleEventOnOutputStream(eventCode)
    }
  }

  fileprivate func handleEventOnInputStream(_ eventCode: Stream.Event) {

    guard self.streamsOpened == true else {
      print("[ThaliCore] VirtualSocket.\(#function) streams are closed")
      return
    }

    switch eventCode {
    case Stream.Event.openCompleted:
      inputStreamOpened = true
      didOpenStreamHandler()
    case Stream.Event.hasBytesAvailable:
      readDataFromInputStream()
    case Stream.Event.hasSpaceAvailable:
      break
    case Stream.Event.errorOccurred:
      print("[ThaliCore] VirtualSocket.\(#function) errorOccurred vsID:\(vsID)")
      closeStreams()
    case Stream.Event.endEncountered:
      print("[ThaliCore] VirtualSocket.\(#function) endEncountered vsID:\(vsID)")
      closeStreams()
      break
    default:
      print("[ThaliCore] VirtualSocket.\(#function) default vsID:\(vsID)")
      break
    }
  }

  fileprivate func handleEventOnOutputStream(_ eventCode: Stream.Event) {

    guard self.streamsOpened == true else {
      print("[ThaliCore] VirtualSocket.\(#function) streams are closed vsID:\(vsID)")
      return
    }

    switch eventCode {
    case Stream.Event.openCompleted:
      outputStreamOpened = true
      didOpenStreamHandler()
    case Stream.Event.hasBytesAvailable:
      break
    case Stream.Event.hasSpaceAvailable:
      print("[ThaliCore] VirtualSocket.\(#function) Event.hasSpaceAvailable")
      writePendingData()
    case Stream.Event.errorOccurred:
      print("[ThaliCore] VirtualSocket.\(#function) errorOccurred vsID:\(vsID)")
      closeStreams()
    case Stream.Event.endEncountered:
      print("[ThaliCore] VirtualSocket.\(#function) endEncountered vsID:\(vsID)")
      closeStreams()
      break
    default:
      print("[ThaliCore] VirtualSocket.\(#function) default vsID:\(vsID)")
      break
    }
  }

  fileprivate func didOpenStreamHandler() {
    if inputStreamOpened && outputStreamOpened {
      didOpenVirtualSocketStreamsHandler?(self)
    }
  }
}
