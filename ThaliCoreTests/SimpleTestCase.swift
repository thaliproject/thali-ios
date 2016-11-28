//
//  SimpleTestCase.swift
//  ThaliCore
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

import SwiftXCTest

class SimpleTestCase: XCTestCase {

  static var allTests = {
    return [
        ("test_example", testExample),
      ]
  }()

  func testExample() {
    XCTAssert(true)
  }
}
