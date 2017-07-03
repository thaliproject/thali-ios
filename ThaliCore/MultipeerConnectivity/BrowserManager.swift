//
//  Thali CordovaPlugin
//  BrowserManager.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

import MultipeerConnectivity

/**
 Manages Thali browser's logic
 */
public final class BrowserManager {

  // MARK: - Public state

  /**
   Bool flag indicates if `BrowserManager` object is listening for advertisements.
   */
  public var listening: Bool {
    return currentBrowser?.listening ?? false
  }

  // MARK: - Internal state

  /**
   `Peer` objects that can be invited into the session.
   */
  internal fileprivate(set) var availablePeers: Atomic<[Peer]> = Atomic([])

  /**
   Active `Relay` objects.
   */
  internal fileprivate(set) var activeRelays: Atomic<[Peer: BrowserRelay]> = Atomic([:])

  // MARK: - Private state

  /**
   Currently active `Browser` object.
   */
  fileprivate var currentBrowser: Browser?

  /**
   The type of service to browse.
   */
  fileprivate let serviceType: String

  /**
   Invite timeout after which the session between peers can be treated as failed.
   */
  fileprivate let inputStreamReceiveTimeout: TimeInterval

  /**
   Handle change of peer availability.
   */
  fileprivate let peerAvailabilityChangedHandler: ([PeerAvailability]) -> Void

  // MARK: - Public state

  /**
   Returns a new `BrowserManager` object.

   - parameters:
     - serviceType:
       The type of service to browse.

     - inputStreamReceiveTimeout:
       Invite timeout after which the session between peers can be treated as failed.

     - peerAvailabilityChangedHandler:
       Called when PeerAvailability is changed.

   - returns:
     An initialized `BrowserManager` object.
   */
  public init(serviceType: String,
              inputStreamReceiveTimeout: TimeInterval,
              peerAvailabilityChanged: @escaping ([PeerAvailability]) -> Void) {
    self.serviceType = serviceType
    self.peerAvailabilityChangedHandler = peerAvailabilityChanged
    self.inputStreamReceiveTimeout = inputStreamReceiveTimeout
  }

  // MARK: - Public methods

  /**
   This method instructs to discover what other devices are within range.

   - parameters:
     - errorHandler:
       Called when advertisement fails.
   */
  public func startListeningForAdvertisements(_ errorHandler: @escaping (Error) -> Void) {
    print("[ThaliCore] BrowserManager.\(#function)")
    if currentBrowser != nil { return }

    let browser = Browser(serviceType: serviceType,
                          foundPeer: foundPeerHandler,
                          lostPeer: lostPeerHandler)

    guard let newBrowser = browser else {
      errorHandler(ThaliCoreError.connectionFailed as Error)
      return
    }

    newBrowser.startListening(errorHandler)
    currentBrowser = newBrowser
  }

  /**
   Stops listening for advertisements.
   */
  public func stopListeningForAdvertisements() {
    print("[ThaliCore] BrowserManager.\(#function)")
    currentBrowser?.stopListening()
    currentBrowser = nil
  }

  /**
   Handle successful connection to peer.
   */
  public typealias ConnectToPeerCompletionHandler = (_ syncValue: String,
                                                     _ error: Error?,
                                                     _ port: UInt16?) -> Void

  /**
   Establish a non-TCP/IP connection to the identified peer and then create a
   TCP/IP bridge on top of that connection which can be accessed by
   opening a TCP/IP connection to the port returned in the callback.

   - parameters:
     - peerIdentifier:
       A value mapped to the UUID part of the remote peer's MCPeerID.
     - syncValue:
       An opaque string that used for tracking callback calls.
     - completion:
       Called when connect succeeded or failed.
   */
  public func connectToPeer(_ peerIdentifier: String,
                            syncValue: String,
                            completion: @escaping ConnectToPeerCompletionHandler) {

    guard let currentBrowser = self.currentBrowser else {
      print("[ThaliCore] BrowserManager.\(#function) peer:\(peerIdentifier) " +
            "error: startListeningNotActive")
      completion(syncValue,
                 ThaliCoreError.startListeningNotActive,
                 nil)
      return
    }

    guard let lastGenerationPeer = self.lastGenerationPeer(for: peerIdentifier) else {
      completion(syncValue,
                 ThaliCoreError.unavailablePeer,
                 nil)
      return
    }

    if let activeRelay = activeRelays.value[lastGenerationPeer] {
      print("[ThaliCore] BrowserManager.\(#function) \(lastGenerationPeer) found active relay")
      completion(syncValue,
                nil,
                activeRelay.listenerPort)
      return
    } else {
      print("[ThaliCore] BrowserManager.\(#function) \(lastGenerationPeer) new relay")
    }

    do {
      let nonTCPsession = try currentBrowser.inviteToConnect(
                                lastGenerationPeer,
                                sessionConnected: {
                                  [weak self] in
                                  guard let strongSelf = self else { return }

                                  print("[ThaliCore] Browser: session connected to " +
                                        "\(lastGenerationPeer)")

                                  let relay = strongSelf.activeRelays.value[lastGenerationPeer]
                                  relay?.openRelay { port, error in
                                    completion(syncValue, error, port)
                                  }
                                },
                                sessionNotConnected: {
                                  [weak self] (previousState: MCSessionState?) in
                                  guard let strongSelf = self else { return }

                                  // An error may occur right away when the session is still
                                  // in the .notConnected state, or after it has reached the
                                  // .connecting state, in those two cases let's call the
                                  // error handler.
                                  if previousState != MCSessionState.connected {
                                    print("[ThaliCore] Browser: session notConnected " +
                                          "failed to connect to \(lastGenerationPeer)")
                                    completion(syncValue,
                                                ThaliCoreError.connectionFailed,
                                                nil)
                                  } else {
                                    print("[ThaliCore] Browser: session notConnected " +
                                          "\(lastGenerationPeer)")
                                  }

                                  strongSelf.activeRelays.modify {
                                    if let relay = $0[lastGenerationPeer] {
                                      relay.closeRelay()
                                    }
                                    $0.removeValue(forKey: lastGenerationPeer)
                                    print("[ThaliCore] Browser: session notConnected " +
                                          "removed relay for \(lastGenerationPeer)")
                                  }
                                })

      activeRelays.modify {
        let relay = BrowserRelay(session: nonTCPsession,
                                 generation: lastGenerationPeer.generation,
                                 createVirtualSocketTimeout: self.inputStreamReceiveTimeout)
        $0[lastGenerationPeer] = relay
      }
    } catch let error {
      print("[ThaliCore] BrowserManager.\(#function) error: \(error)")
      completion(syncValue, error, nil)
    }
  }

  /**
   - parameters:
     - peerIdentifier:
       A value mapped to the UUID part of the remote peer's MCPeerID.
   */
  public func disconnect(_ peerIdentifier: String) {
    print("[ThaliCore] BrowserManager.\(#function) peer:\(peerIdentifier)")

    let itemsToClose = activeRelays.withValue {
      $0.filter { $0.key.uuid == peerIdentifier }
    }

    for item in itemsToClose {
      item.value.closeRelay()
      activeRelays.modify {
        $0[item.key] = nil
      }
    }
  }

  // MARK: - Internal methods

  /**
   Returns the highest generation advertised for given peerIdentifier.

   - parameters:
     - peerIdentifier:
       A value mapped to the UUID part of the remote peer's MCPeerID.

   - returns:
     `Peer` object with the highest generation advertised for given *peerIdentifier*.
     If there are no peers with given *peerIdentifier*, return nil.
   */
  func lastGenerationPeer(for peerIdentifier: String) -> Peer? {
    return availablePeers.withValue {
      $0
      .filter { $0.uuid == peerIdentifier }
      .max { $0.0.generation < $0.1.generation }
    }
  }

  // MARK: - Private handlers

  /**
   Handle finding nearby peer.

   - parameters:
     - peer:
       `Peer` object which was founded.
   */
  fileprivate func foundPeerHandler(_ peer: Peer) {
    print("[ThaliCore] BrowserManager.\(#function) peer:\(peer)")
    availablePeers.modify { $0.append(peer) }

    let updatedPeerAvailability = PeerAvailability(peer: peer, available: true)
    peerAvailabilityChangedHandler([updatedPeerAvailability])
  }

  /**
   Handle losing nearby peer.

   - parameters:
     - peer:
       `Peer` object which was lost.
   */
  fileprivate func lostPeerHandler(_ peer: Peer) {
    print("[ThaliCore] BrowserManager.\(#function) peer:\(peer)")
    guard let lastGenerationPeer = self.lastGenerationPeer(for: peer.uuid) else {
      return
    }

    availablePeers.modify {
      if let indexOfLostPeer = $0.index(of: peer) {
        $0.remove(at: indexOfLostPeer)
      }
    }

    // This will trigger the sessionNotConnected handler that will
    // remove the relay from the activeRelays list.
    self.activeRelays.value[peer]?.disconnectNonTCPSession()

    if peer == lastGenerationPeer {
      let updatedPeerAvailability = PeerAvailability(peer: peer, available: false)
      peerAvailabilityChangedHandler([updatedPeerAvailability])
    }
  }
}
