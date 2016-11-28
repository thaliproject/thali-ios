//
//  TestCases.swift
//  ThaliCore
//
//  Created by Ilya Laryionau on 28/11/2016.
//  Copyright © 2016 Thali. All rights reserved.
//

import Foundation
import SwiftXCTest

internal func rootTestSuite() -> XCTestSuite {
    let rootTestSuite = XCTestSuite(name: "All tests")

    let currentTestSuite = XCTestSuite(
      name: "All tests",
      testCases: [
          testCase(AtomicTests.allTests),
          testCase(PeerTests.allTests),
          testCase(AppStateNotificationsManagerTests.allTests),
        ]
    )
  
    rootTestSuite.addTest(currentTestSuite)
  
    return rootTestSuite
}
