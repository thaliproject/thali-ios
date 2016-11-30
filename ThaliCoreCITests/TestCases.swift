//
//  TestCases.swift
//  ThaliCore
//
//  Created by Ilya Laryionau on 28/11/2016.
//  Copyright © 2016 Thali. All rights reserved.
//

import Foundation
import SwiftXCTest

public struct ThaliCore {
  public static var allTestCases: [XCTestCaseEntry] {
    return [
      testCase(AtomicTests.allTests),
      testCase(PeerTests.allTests),
      testCase(AppStateNotificationsManagerTests.allTests),
    ]
  }
}
