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

  /**
   Max retries if an error occurs while trying to connect to the remote peer.
   */
  static let maxConnectionRetries = 3

  /**
   Mutex used to synchronize connectToPeer() and lostPeerHandler().
  */
  let mutex: PosixThreadMutex

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
    self.mutex = PosixThreadMutex()
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
                            retryCount: Int = 0,
                            completion: @escaping ConnectToPeerCompletionHandler) {

    guard retryCount <= BrowserManager.maxConnectionRetries else {
      print("[ThaliCore] BrowserManager.\(#function) peer:\(peerIdentifier) " +
            "error: max retries exceeded")
      completion(syncValue,
                 ThaliCoreError.connectionFailed,
                 nil)
      return
    }

    guard let currentBrowser = self.currentBrowser else {
      print("[ThaliCore] BrowserManager.\(#function) peer:\(peerIdentifier) " +
            "error: startListeningNotActive")
      completion(syncValue,
                 ThaliCoreError.startListeningNotActive,
                 nil)
      return
    }

    // connectToPeer() and lostPeerHandler() may run into race conditions if not synchronized.
    mutex.lock()
    defer { mutex.unlock() }

    guard let lastGenerationPeer = self.lastGenerationPeer(for: peerIdentifier) else {
      print("[ThaliCore] BrowserManager.\(#function) peer:\(peerIdentifier) " +
            "error: peer is unavailable")
      completion(syncValue,
                 ThaliCoreError.peerIsUnavailable,
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
      print("[ThaliCore] BrowserManager.\(#function) \(lastGenerationPeer) creating a new relay")
    }

    do {
      let session = try currentBrowser.inviteToConnect(
                          lastGenerationPeer,
                          sessionConnected: {
                            [weak self, lastGenerationPeer] in
                            guard let strongSelf = self else { return }

                            print("[ThaliCore] Browser: session connected to " +
                                  "\(lastGenerationPeer)")

                            let relay = strongSelf.activeRelays.value[lastGenerationPeer]
                            relay?.openRelay { port, error in
                              completion(syncValue, error, port)
                            }
                          },
                          sessionNotConnected: {
                            [weak self, lastGenerationPeer] (previousState: MCSessionState?) in
                            guard let strongSelf = self else { return }

                            strongSelf.activeRelays.modify { activeRelay in
                              if let relay = activeRelay[lastGenerationPeer] {
                                relay.closeRelay()
                              }
                              activeRelay.removeValue(forKey: lastGenerationPeer)
                            }

                            if previousState == MCSessionState.connected {
                              // The session may have disconnected because the application
                              // has explicitly closed the connection to the remote peer
                              // or because an error occurred.
                              // If an error occurred, the application should have already
                              // been notified by the error handler of the tcp connection,
                              // here we simply notify the event and let the application
                              // deal with it if it registered for this event.
                              print("[ThaliCore] Browser: session notConnected " +
                                    "fire notification for \(lastGenerationPeer)")
                              completion(syncValue,
                                         ThaliCoreError.sessionDisconnected,
                                         nil)
                            } else {
                              // An error may occur when the session is still in the
                              // 'notConnected' state or after it has reached the
                              // 'connecting' state but it's not yet 'connected', in those
                              // two cases let's retry to connect to the remote peer.
                              print("[ThaliCore] Browser: session notConnected retry " +
                                    "count #\(retryCount) for \(lastGenerationPeer)")
                              strongSelf.connectToPeer(peerIdentifier,
                                                       syncValue: syncValue,
                                                       retryCount: retryCount + 1,
                                                       completion: completion)
                            }
                          })

      activeRelays.modify { activeRelays in
        let relay = BrowserRelay(session: session,
                                 generation: lastGenerationPeer.generation,
                                 createVirtualSocketTimeout: self.inputStreamReceiveTimeout)
        activeRelays[lastGenerationPeer] = relay
      }
    } catch let error {
      print("[ThaliCore] BrowserManager.\(#function) error:\(error)")
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

    let itemsToClose = activeRelays.withValue { activeRelays in
      activeRelays.filter { activeRelay in
        activeRelay.key.uuid == peerIdentifier
      }
    }

    for item in itemsToClose {
      item.value.closeRelay()
      activeRelays.modify { activeRelays in
        activeRelays[item.key] = nil
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
    return availablePeers.withValue { availablePeers in
      availablePeers
        .filter { availablePeer in
          availablePeer.uuid == peerIdentifier
        }
        .max { availablePeer in
          availablePeer.0.generation < availablePeer.1.generation
      }
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
    availablePeers.modify { availablePeers in
      availablePeers.append(peer)
    }

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

    // While processing a lost peer and removing its activeRelay, we need to make
    // sure that connectToPeer() doesn't process incoming requests since it could
    // run into race conditions.
    mutex.lock()
    defer { mutex.unlock() }

    availablePeers.modify { availablePeers in
      if let indexOfLostPeer = availablePeers.index(of: peer) {
        availablePeers.remove(at: indexOfLostPeer)
      }
    }

    self.activeRelays.modify { activeRelays in
      if let relay = activeRelays[peer] {
        if relay.state == BrowserRelay.RelayState.connected {
          // If the relay is stil connecting or if it's already disconnecting
          // let the connection/disconnection logic take care of dealing with
          // the 'relay' instance.
          relay.closeRelay()
          activeRelays.removeValue(forKey: peer)
          print("[ThaliCore] BrowserManager.\(#function) peer:\(peer) relay removed")
        }
      }
    }

    if peer == lastGenerationPeer {
      let updatedPeerAvailability = PeerAvailability(peer: peer, available: false)
      peerAvailabilityChangedHandler([updatedPeerAvailability])
    }
  }
}
