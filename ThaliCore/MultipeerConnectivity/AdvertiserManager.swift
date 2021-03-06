//
//  Thali CordovaPlugin
//  AdvertiserManager.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

import MultipeerConnectivity

/**
 Manages Thali advertiser's logic
 */
public final class AdvertiserManager {

  // MARK: - Public state

  /**
   Bool flag indicates if advertising is active.
   */
  public var advertising: Bool {
    return currentAdvertiser?.advertising ?? false
  }

  // MARK: - Internal state

  /**
   Active `Advertiser` objects.
   */
  internal fileprivate(set) var advertisers: Atomic<[Advertiser]> = Atomic([])

  /**
   Active `Relay` objects.
   */
  internal fileprivate(set) var activeRelays: Atomic<[String: AdvertiserRelay]> = Atomic([:])

  /**
   Handle disposing advertiser after timeout.
   */
  internal var didDisposeOfAdvertiserForPeerHandler: ((Peer) -> Void)?

  // MARK: - Private state

  /**
   Currently active `Advertiser` object.
   */
  fileprivate var currentAdvertiser: Advertiser?

  /**
   The type of service to advertise.
   */
  fileprivate let serviceType: String

  /**
   Timeout after which advertiser gets disposed of.
   */
  fileprivate let disposeTimeout: DispatchTimeInterval

  // MARK: - Initialization

  /**
   Returns a new `AdvertiserManager` object.

   - parameters:
     - serviceType:
       The type of service to advertise.

     - disposeAdvertiserTimeout:
       Timeout after which advertiser gets disposed of.

   - returns:
   An initialized `AdvertiserManager` object.
   */
  public init(serviceType: String, disposeAdvertiserTimeout: TimeInterval) {
    self.serviceType = serviceType
    self.disposeTimeout = .seconds(Int(disposeAdvertiserTimeout))
  }

  // MARK: - Public methods

  /**
   This method has two separate but related functions.

   It's first function is to begin advertising the Thali peer's presence to other peers.

   The second purpose is to bridge outgoing non-TCP/IP connections to TCP/IP port.

   - parameters:
     - port:
       Pre-configured localhost port that a native TCP/IP client should
       use to bridge outgoing non-TCP/IP connection.

     - errorHandler:
       Called when startUpdateAdvertisingAndListening fails.
   */
  public func startUpdateAdvertisingAndListening(onPort port: UInt16,
                                                 errorHandler: @escaping (Error) -> Void) {
    if let currentAdvertiser = currentAdvertiser {
      disposeOfAdvertiserAfterTimeoutToFinishInvites(currentAdvertiser)
    }

    let newPeer = currentAdvertiser?.peer.nextGenerationPeer() ?? Peer()
    print("[ThaliCore] AdvertiserManager.\(#function) \(newPeer)")

    let advertiser = Advertiser(peer: newPeer,
                                serviceType: serviceType,
                                receivedInvitation: { [weak self] session in
                                  guard let strongSelf = self else { return }

                                  print("[ThaliCore] Advertiser: session connected " +
                                        "\(newPeer)")
                                  strongSelf.activeRelays.modify { activeRelays in
                                    let relay = AdvertiserRelay(with: session, on: port)
                                    activeRelays[newPeer.uuid] = relay
                                  }
                                },
                                sessionNotConnected: {
                                  [weak self] (previousState: MCSessionState?) in
                                  guard let strongSelf = self else { return }

                                  print("[ThaliCore] Advertiser: session notConnected " +
                                        "\(newPeer)")
                                  strongSelf.activeRelays.modify { activeRelays in
                                    if let relay = activeRelays[newPeer.uuid] {
                                      relay.closeRelay()
                                    }
                                    activeRelays.removeValue(forKey: newPeer.uuid)
                                  }
                                })

    guard let newAdvertiser = advertiser else {
      errorHandler(ThaliCoreError.connectionFailed as Error)
      return
    }

    advertisers.modify { advertisers in
      newAdvertiser.startAdvertising(errorHandler)
      advertisers.append(newAdvertiser)
    }

    self.currentAdvertiser = newAdvertiser
  }

  /**
   Dispose of all advertisers.
   */
  public func stopAdvertising() {
    print("[ThaliCore] AdvertiserManager.\(#function)")
    advertisers.modify { advertisers in
      advertisers.forEach { advertiser in
        advertiser.stopAdvertising()
      }
      advertisers.removeAll()
    }
    currentAdvertiser = nil
  }

  /**
   Checks if `AdvertiserManager` has advertiser with a given identifier.

   - parameters:
     - identifier:
       UUID part of the `Peer`.

   - returns:
     Bool value indicates if `AdvertiserManager` has advertiser with given identifier.
   */
  public func hasAdvertiser(with identifier: String) -> Bool {
    return advertisers.value.filter { advertiser in
      advertiser.peer.uuid == identifier
      }
      .count > 0
  }

  // MARK: - Private methods

  /**
   Disposes of advertiser after timeout.

   In any case when a peer starts a new underlying `MCNearbyServiceAdvertiser` object
   it MUST keep the old object for at least *disposeTimeout*.
   This is to allow any in progress invites to finish.
   After *disposeTimeout* the old `MCNearbyServiceAdvertiser` objects MUST be closed.

   - parameters:
     - advertiserToBeDisposedOf:
       `Advertiser` object that should be disposed of after `disposeTimeout`.
   */
  fileprivate func disposeOfAdvertiserAfterTimeoutToFinishInvites(
                      _ advertiserToBeDisposedOf: Advertiser) {
    let disposeTimeout: DispatchTime = .now() + self.disposeTimeout

    DispatchQueue.main.asyncAfter(deadline: disposeTimeout) {
      [weak self,
      weak advertiserToBeDisposedOf] in
      guard let strongSelf = self else { return }
      guard let advertiserShouldBeDisposed = advertiserToBeDisposedOf else { return }

      strongSelf.advertisers.modify { advertisers in
        advertiserShouldBeDisposed.stopAdvertising()
        if let indexOfDisposingAdvertiser = advertisers.index(of: advertiserShouldBeDisposed) {
          advertisers.remove(at: indexOfDisposingAdvertiser)
        }
      }

      strongSelf.didDisposeOfAdvertiserForPeerHandler?(advertiserShouldBeDisposed.peer)
    }
  }
}
