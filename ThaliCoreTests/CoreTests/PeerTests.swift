//
//  Thali CordovaPlugin
//  PeerTests.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

@testable import ThaliCore
import SwiftXCTest

class PeerTests: XCTestCase {

  static var allTests = {
    return [
      ("test_peerByNextGenerationCallShouldHaveSameUUIDPart",
        testPeerByNextGenerationCallShouldHaveSameUUIDPart),
      ("test_genetationByNextGenerationCallShouldBeIncreasedByOne",
        testGenetationByNextGenerationCallShouldBeIncreasedByOne),
      ("test_stringValueHasCorrectForm", testStringValueHasCorrectForm),
      ("test_initWithStringHasTwoSeparatorsCausesError",
        testInitWithStringHasTwoSeparatorsCausesError),
      ("test_initWithStringHasNoSeparatorCausesError",
        testInitWithStringHasNoSeparatorCausesError),
      ("test_initWithStringHasInvalidUUIDPartCausesError",
        testInitWithStringHasInvalidUUIDPartCausesError),
      ("test_initWithStringHasNotNumberGenerationCausesError",
        testInitWithStringHasNotNumberGenerationCausesError),
      ("test_generationsEquality",
        testGenerationsEquality),
    ]
  }()

  // MARK: - Tests
  func testPeerByNextGenerationCallShouldHaveSameUUIDPart() {
    let peer = Peer()
    let nextGenPeer = peer.nextGenerationPeer()
    XCTAssertEqual(peer.uuid, nextGenPeer.uuid)
  }

  func testGenetationByNextGenerationCallShouldBeIncreasedByOne() {
    let peer = Peer()
    let nextGenPeer = peer.nextGenerationPeer()
    XCTAssertEqual(peer.generation + 1, nextGenPeer.generation)
  }

  func testStringValueHasCorrectForm() {
    for i in 0...0xF {
      let uuid = UUID().uuidString
      let string = "\(uuid):\(String(i, radix: 16))"
      let peer = try? Peer(stringValue: string)
      XCTAssertEqual(peer?.uuid, uuid)
      XCTAssertEqual(peer?.generation, i)
    }
  }

  func testInitWithStringHasTwoSeparatorsCausesError() {
    let string = String.random(length: 4) + ":" +
      String.random(length: 4) + ":" +
      String.random(length: 4)
    var parsingError: ThaliCoreError?
    do {
      let _ = try Peer(stringValue: string)
    } catch let peerErr as ThaliCoreError {
      parsingError = peerErr
    } catch _ {
    }
    XCTAssertEqual(parsingError, .IllegalPeerID)
  }

  func testInitWithStringHasNoSeparatorCausesError() {
    let string = String.random(length: 4)
    var parsingError: ThaliCoreError?
    do {
      let _ = try Peer(stringValue: string)
    } catch let peerErr as ThaliCoreError {
      parsingError = peerErr
    } catch _ {
    }
    XCTAssertEqual(parsingError, .IllegalPeerID)
  }

  func testInitWithStringHasInvalidUUIDPartCausesError() {
    let string = "---" + ":" + "0"
    var parsingError: ThaliCoreError?
    do {
      let _ = try Peer(stringValue: string)
    } catch let peerErr as ThaliCoreError {
      parsingError = peerErr
    } catch _ {
    }
    XCTAssertEqual(parsingError, .IllegalPeerID)
  }

  func testInitWithStringHasNotNumberGenerationCausesError() {
    let string = String.random(length: 4) + ":" + "not_a_number"
    var parsingError: ThaliCoreError?
    do {
      let _ = try Peer(stringValue: string)
    } catch let peerErr as ThaliCoreError {
      parsingError = peerErr
    } catch _ {
    }
    XCTAssertEqual(parsingError, .IllegalPeerID)
  }

  func testGenerationsEquality() {
    let peerID1 = Peer()
    do {
      let peerID2 = try Peer(uuidIdentifier: peerID1.uuid, generation: peerID1.generation + 1)
      XCTAssertNotEqual(peerID1, peerID2)
    } catch let error {
      XCTFail("unexpected error \(error)")
    }
  }
}