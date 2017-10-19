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
  fileprivate var dataQueue: [Data] = []
  fileprivate let dataQueueMutex: PosixThreadMutex
  fileprivate let streamsMutex: PosixThreadMutex
  fileprivate var writingPendingData = false

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
    self.streamsMutex = PosixThreadMutex()
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
    streamsMutex.lock()
    defer { streamsMutex.unlock() }

    guard self.streamsOpened == false else {
      return
    }

    self.streamsOpened = true

    DispatchQueue.global(qos: .utility).async {
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
    }
  }

  func closeStreams() {
    print("[ThaliCore] VirtualSocket.\(#function) vsID:\(vsID)")
    streamsMutex.lock()
    defer {
      streamsMutex.unlock()
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

    guard outputStream != nil else {
      return
    }

    dataQueueMutex.lock()
    dataQueue.append(data)
    print("[ThaliCore] VirtualSocket.\(#function) len:\(data.count) " +
          "count:\(dataQueue.count) vsID:\(vsID)")
    if writingPendingData == false {
      DispatchQueue.global(qos: .userInitiated).async {
        self.writePendingData()
      }
    }
    dataQueueMutex.unlock()
  }

  // Event handler for Stream.Event.hasSpaceAvailable also called by writeDataToOutputStream
  func writePendingData() {

    guard let strongOuputStream = self.outputStream else {
      print("[ThaliCore] VirtualSocket.\(#function) stream is nil vsID:\(vsID)")
      dataQueueMutex.lock()
      dataQueue.removeAll()
      dataQueueMutex.unlock()
      return
    }

    dataQueueMutex.lock()
    if writingPendingData == false {
      writingPendingData = true
    } else {
      dataQueueMutex.unlock()
      return
    }
    dataQueueMutex.unlock()

    while dataQueue.count > 0 {
      dataQueueMutex.lock()
      let data = dataQueue.removeFirst()
      dataQueueMutex.unlock()

      var bytesRemaining = data.count
      var totalBytesWritten = 0

      while bytesRemaining > 0 {
        let chunkLength = (bytesRemaining > maxReadWriteBufferLength) ?
                          maxReadWriteBufferLength : bytesRemaining

        let bytesWritten = data.withUnsafeBytes { bytes in
          strongOuputStream.write(bytes.advanced(by: totalBytesWritten),
                                  maxLength: chunkLength)
        }

        if bytesWritten == chunkLength {
          totalBytesWritten += bytesWritten
          bytesRemaining -= bytesWritten
        } else if bytesWritten == 0 {
          // Requeue the remaining data on top of the queue and wait
          // for the 'hasSpaceAvailable' event to be fired
          print("[ThaliCore] VirtualSocket.\(#function) _ZERO_ bytes written vsID:\(vsID)")
          let remainingData = data.subdata(in: totalBytesWritten..<(totalBytesWritten +
                                                                    bytesRemaining))
          dataQueueMutex.lock()
          dataQueue.insert(remainingData, at: 0)
          dataQueueMutex.unlock()
          break
        } else if bytesWritten == -1 {
          print("[ThaliCore] VirtualSocket.\(#function) _ERROR_ " +
                "chunkLength:\(chunkLength) written:\(bytesWritten) vsID:\(vsID)")
          dataQueueMutex.lock()
          dataQueue.removeAll()
          dataQueueMutex.unlock()
          break
        }
      }

      print("[ThaliCore] VirtualSocket.\(#function) to write:\(data.count) " +
            "written:\(totalBytesWritten) count:\(dataQueue.count) vsID:\(vsID)")
    }
    writingPendingData = false
  }

  // Event handler for Stream.Event.hasBytesAvailable
  fileprivate func readDataFromInputStream() {

    guard let strongInputStream = self.inputStream else {
      return
    }

    var buffer = [UInt8](repeating: 0, count: maxReadWriteBufferLength)

    let bytesReaded = strongInputStream.read(&buffer, maxLength: maxReadWriteBufferLength)
    print("[ThaliCore] VirtualSocket.\(#function) read: \(bytesReaded) vsID:\(vsID)")
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
      print("[ThaliCore] VirtualSocket.\(#function) hasSpaceAvailable vsID:\(vsID)")
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
