//
//  Thali CordovaPlugin
//  ThaliCoreError.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

public enum  ThaliCoreError: String, CustomNSError, LocalizedError {

  case startListeningNotActive = "startListeningForAdvertisements is not active"
  case connectionFailed = "Connection could not be established"
  case connectionTimedOut = "Connection wait timed out"
  case maxConnectionsReached = "Max connections reached"
  case noNativeNonTCPSupport = "No Native Non-TCP Support"
  case noAvailableTCPPorts = "No available TCP ports"
  case radioTurnedOff = "Radio Turned Off"
  case unspecifiedRadioError = "Unspecified Error with Radio infrastructure"
  case illegalPeerID = "Illegal peerID"

  public static var errorDomain: String {
    return "org.thaliproject.ThaliCoreError"
  }

  public var errorCode: Int {
    switch self {
    case .startListeningNotActive:
      return 0
    case .connectionFailed:
      return 1
    case .connectionTimedOut:
      return 2
    case .maxConnectionsReached:
      return 3
    case .noNativeNonTCPSupport:
      return 4
    case .noAvailableTCPPorts:
      return 5
    case .radioTurnedOff:
      return 6
    case .unspecifiedRadioError:
      return 7
    case .illegalPeerID:
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
