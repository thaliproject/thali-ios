//
//  Thali CordovaPlugin
//  VirtualSocketTests.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

import MultipeerConnectivity
@testable import ThaliCore
import SwiftXCTest

class VirtualSocketTests: XCTestCase {

  // MARK: - State
  var mcPeerID: MCPeerID!
  var mcSessionMock: MCSessionMock!
  var nonTCPSession: Session!

  let streamReceivedTimeout: TimeInterval = 5.0
  let virtualSocketOpenTimeout: TimeInterval = 5.0
  let virtualSocketCloseTimeout: TimeInterval = 5.0

  // MARK: - Setup & Teardown
  override func setUp() {
    super.setUp()
    mcPeerID = MCPeerID(displayName: String.random(length: 5))
    mcSessionMock = MCSessionMock(peer: MCPeerID(displayName: String.random(length: 5)))
    nonTCPSession = Session(session: mcSessionMock,
                            identifier: mcPeerID,
                            connected: {},
                            notConnected: {_ in })
  }

  override func tearDown() {
    mcPeerID = nil
    mcSessionMock = nil
    nonTCPSession = nil
    super.tearDown()
  }

  // MARK: - Tests
  func testVirtualSocketCreatedWithClosedState() {
    // Given
    let ouputStream = nonTCPSession.startOutputStream(with: "test")
    guard ouputStream != nil else {
      XCTFail("Can't create output stream on mock Session")
      return
    }

    let emptyData = Data(bytes: [], count: 0)
    let inputStream = InputStream(data: emptyData)

    // When
    let virtualSocket = VirtualSocket(inputStream: inputStream, outputStream: ouputStream!)

    // Then
    XCTAssertFalse(virtualSocket.streamsOpened)
  }

  func testVirtualSocketOpenStreamsChangesState() {
    // Given
    let ouputStream = nonTCPSession.startOutputStream(with: "test")
    guard ouputStream != nil else {
      XCTFail("Can't create output stream on mock Session")
      return
    }

    let emptyData = Data(bytes: [], count: 0)
    let inputStream = InputStream(data: emptyData)

    let virtualSocket = VirtualSocket(inputStream: inputStream, outputStream: ouputStream!)
    XCTAssertFalse(virtualSocket.streamsOpened)

    // When
    virtualSocket.openStreams()
    XCTAssertTrue(virtualSocket.streamsOpened)
  }

  func testVirtualSocketCloseStreams() {
    // Given
    let ouputStream = nonTCPSession.startOutputStream(with: "test")
    guard ouputStream != nil else {
      XCTFail("Can't create output stream on mock Session")
      return
    }

    let emptyData = Data(bytes: [], count: 0)
    let inputStream = InputStream(data: emptyData)

    let virtualSocket = VirtualSocket(inputStream: inputStream, outputStream: ouputStream!)
    XCTAssertFalse(virtualSocket.streamsOpened)
    virtualSocket.openStreams()
    XCTAssertTrue(virtualSocket.streamsOpened)

    // When
    virtualSocket.closeStreams()

    // Then
    XCTAssertFalse(virtualSocket.streamsOpened)

  }

  func testOpenStreamsCalledTwiceChangesStateProperly() {
    // Given
    let ouputStream = nonTCPSession.startOutputStream(with: "test")
    guard ouputStream != nil else {
      XCTFail("Can't create output stream on mock Session")
      return
    }

    let emptyData = Data(bytes: [], count: 0)
    let inputStream = InputStream(data: emptyData)

    let virtualSocket = VirtualSocket(inputStream: inputStream, outputStream: ouputStream!)
    XCTAssertFalse(virtualSocket.streamsOpened)

    // When
    virtualSocket.openStreams()
    virtualSocket.openStreams()

    // Then
    XCTAssertTrue(virtualSocket.streamsOpened)
  }

  func testCloseStreamsCalledTwiceChangesStateProperly() {
    // Given
    let ouputStream = nonTCPSession.startOutputStream(with: "test")
    guard ouputStream != nil else {
      XCTFail("Can't create output stream on mock Session")
      return
    }

    let emptyData = Data(bytes: [], count: 0)
    let inputStream = InputStream(data: emptyData)

    let virtualSocket = VirtualSocket(inputStream: inputStream, outputStream: ouputStream!)
    XCTAssertFalse(virtualSocket.streamsOpened)
    virtualSocket.openStreams()

    // When
    virtualSocket.closeStreams()
    virtualSocket.closeStreams()

    // Then
    XCTAssertFalse(virtualSocket.streamsOpened)
  }
}
