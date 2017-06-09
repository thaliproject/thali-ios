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
  internal var opened: Atomic<Bool>
  internal var didOpenVirtualSocketHandler: ((VirtualSocket) -> Void)?
  internal var didReadDataFromStreamHandler: ((VirtualSocket, Data) -> Void)?
  internal var didCloseVirtualSocketHandler: ((VirtualSocket) -> Void)?

  // MARK: - Private state
  fileprivate var inputStream: InputStream
  fileprivate var outputStream: OutputStream

  fileprivate var runLoop: RunLoop?

  fileprivate var inputStreamOpened = false
  fileprivate var outputStreamOpened = false

  let maxReadBufferLength = 1024
  fileprivate var pendingDataToWrite: NSMutableData?

  // MARK: - Initialize
  init(with inputStream: InputStream, outputStream: OutputStream) {
    self.opened = Atomic(false)
    self.inputStream = inputStream
    self.outputStream = outputStream
    super.init()
  }

  deinit {
    print("[ThaliCore] VirtualSocket.\(#function)")
  }

  // MARK: - Internal methods
  func openStreams() {
    var proceed = false
    self.opened.modify {
      if $0 == false {
        $0 = true
        proceed = true
      }
    }

    guard proceed else {
      return
    }

    let queue = DispatchQueue.global(qos: .default)
    queue.async(execute: {
      self.runLoop = RunLoop.current

      self.inputStream.delegate = self
      self.inputStream.schedule(in: self.runLoop!,
        forMode: RunLoopMode.defaultRunLoopMode)
      self.inputStream.open()

      self.outputStream.delegate = self
      self.outputStream.schedule(in: self.runLoop!,
        forMode: RunLoopMode.defaultRunLoopMode)
      self.outputStream.open()

      RunLoop.current.run(until: Date.distantFuture)
      print("[ThaliCore] VirtualSocket exited RunLoop")
    })
  }

  func closeStreams() {
    print("[ThaliCore] VirtualSocket.\(#function)")
    var proceed = false
    self.opened.modify {
      if $0 == true {
        $0 = false
        proceed = true
      }
    }

    guard proceed else {
      return
    }

    inputStream.close()
    inputStream.remove(from: self.runLoop!, forMode: RunLoopMode.defaultRunLoopMode)
    inputStreamOpened = false

    outputStream.close()
    outputStream.remove(from: self.runLoop!, forMode: RunLoopMode.defaultRunLoopMode)
    outputStreamOpened = false

    CFRunLoopStop(self.runLoop!.getCFRunLoop())

    didCloseVirtualSocketHandler?(self)
  }

  func writeDataToOutputStream(_ data: Data) {
    if !outputStream.hasSpaceAvailable {
      pendingDataToWrite?.append(data)
      return
    }

    let dataLength = data.count
    let startDataPointer = (data as NSData).bytes.bindMemory(to: UInt8.self, capacity: data.count)
    let buffer: [UInt8] = Array(
      UnsafeBufferPointer(start: startDataPointer, count: dataLength)
    )

    let bytesWritten = outputStream.write(buffer, maxLength: dataLength)
    if bytesWritten < 0 {
      closeStreams()
    }
  }

  func writePendingData() {
    guard let dataToWrite = pendingDataToWrite else {
      return
    }

    pendingDataToWrite = nil
    writeDataToOutputStream(dataToWrite as Data)
  }

  fileprivate func readDataFromInputStream() {
    var buffer = [UInt8](repeating: 0, count: maxReadBufferLength)

    let bytesReaded = self.inputStream.read(&buffer, maxLength: maxReadBufferLength)
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
    } else {
      assertionFailure()
    }
  }

  fileprivate func handleEventOnInputStream(_ eventCode: Stream.Event) {

    guard self.opened.value == true else {
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
      closeStreams()
    case Stream.Event.endEncountered:
      break
    default:
      break
    }
  }

  fileprivate func handleEventOnOutputStream(_ eventCode: Stream.Event) {

    guard self.opened.value == true else {
      return
    }

    switch eventCode {
    case Stream.Event.openCompleted:
      outputStreamOpened = true
      didOpenStreamHandler()
    case Stream.Event.hasBytesAvailable:
      break
    case Stream.Event.hasSpaceAvailable:
      writePendingData()
    case Stream.Event.errorOccurred:
      closeStreams()
    case Stream.Event.endEncountered:
      break
    default:
      break
    }
  }

  fileprivate func didOpenStreamHandler() {
    if inputStreamOpened && outputStreamOpened {
      didOpenVirtualSocketHandler?(self)
    }
  }
}
