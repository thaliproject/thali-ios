//
//  Thali CordovaPlugin
//  ThaliCoreError.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

public enum ThaliCoreError: String, CustomNSError, LocalizedError {

  case StartListeningNotActive = "startListeningForAdvertisements is not active"
  case ConnectionFailed = "Connection could not be established"
  case ConnectionTimedOut = "Connection wait timed out"
  case MaxConnectionsReached = "Max connections reached"
  case NoNativeNonTCPSupport = "No Native Non-TCP Support"
  case NoAvailableTCPPorts = "No available TCP ports"
  case RadioTurnedOff = "Radio Turned Off"
  case UnspecifiedRadioError = "Unspecified Error with Radio infrastructure"
  case IllegalPeerID = "Illegal peerID"

  public static var errorDomain: String {
    return "org.thaliproject.ThaliCoreError"
  }

  public var errorCode: Int {
    switch self {
    case .StartListeningNotActive:
      return 0
    case .ConnectionFailed:
      return 1
    case .ConnectionTimedOut:
      return 2
    case .MaxConnectionsReached:
      return 3
    case .NoNativeNonTCPSupport:
      return 4
    case .NoAvailableTCPPorts:
      return 5
    case .RadioTurnedOff:
      return 6
    case .UnspecifiedRadioError:
      return 7
    case .IllegalPeerID:
      return 8
    }
  }

  /// The user-info dictionary.
  public var errorUserInfo: [String : Any] {
    return [NSLocalizedDescriptionKey: errorDescription ?? description]
  }

  public var description: String {
    return rawValue
  }

  public var errorDescription: String? {
    return description
  }
}
