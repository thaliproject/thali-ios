//
//  TestCases.swift
//  ThaliCore
//
//  Created by Ilya Laryionau on 28/11/2016.
//  Copyright © 2016 Thali. All rights reserved.
//

import SwiftXCTest

public struct ThaliCoreTests {
  public static var allTests: [XCTestCaseEntry] {
    return [
      testCase([
        ("testWillEnterBackground", AppStateNotificationsManagerTests.testWillEnterBackground),
        ("testDidEnterForeground", AppStateNotificationsManagerTests.testDidEnterForeground),
      ]),
      testCase([
        ("testGetCorrectValueWithValueProperty", AtomicTests.testGetCorrectValueWithValueProperty),
        ("testGetCorrectValueAfterModify", AtomicTests.testGetCorrectValueAfterModify),
        ("testGetCorrectValueWithValueFunction", AtomicTests.testGetCorrectValueWithValueFunction),
        ("testLockOnReadWrite", AtomicTests.testLockOnReadWrite),
      ]),
      testCase([
        ("testPeerByNextGenerationCallShouldHaveSameUUIDPart", PeerTests.testPeerByNextGenerationCallShouldHaveSameUUIDPart),
        ("testGenetationByNextGenerationCallShouldBeIncreasedByOne", PeerTests.testGenetationByNextGenerationCallShouldBeIncreasedByOne),
        ("testStringValueHasCorrectForm", PeerTests.testStringValueHasCorrectForm),
        ("testInitWithStringHasTwoSeparatorsCausesError", PeerTests.testInitWithStringHasTwoSeparatorsCausesError),
        ("testInitWithStringHasNoSeparatorCausesError", PeerTests.testInitWithStringHasNoSeparatorCausesError),
        ("testInitWithStringHasInvalidUUIDPartCausesError", PeerTests.testInitWithStringHasInvalidUUIDPartCausesError),
        ("testInitWithStringHasNotNumberGenerationCausesError", PeerTests.testInitWithStringHasNotNumberGenerationCausesError),
        ("testGenerationsEquality", PeerTests.testGenerationsEquality),
      ]),
      testCase([
        ("testStartAdvertisingChangesState", AdvertiserManagerTests.testStartAdvertisingChangesState),
        ("testStopAdvertisingWithoutCallingStartIsNOTError", AdvertiserManagerTests.testStopAdvertisingWithoutCallingStartIsNOTError),
        ("testStopAdvertisingTwiceWithoutCallingStartIsNOTError", AdvertiserManagerTests.testStopAdvertisingTwiceWithoutCallingStartIsNOTError),
        ("testStartAdvertisingTwice", AdvertiserManagerTests.testStartAdvertisingTwice),
        ("testStartStopAdvertisingChangesInternalNumberOfAdvertisers", AdvertiserManagerTests.testStartStopAdvertisingChangesInternalNumberOfAdvertisers),
        ("testStartAdvertisingTwiceChangesInternalNumberOfAdvertisers", AdvertiserManagerTests.testStartAdvertisingTwiceChangesInternalNumberOfAdvertisers),
        ("testStartStopStartAdvertisingChangesInternalNumberOfAdvertisers", AdvertiserManagerTests.testStartStopStartAdvertisingChangesInternalNumberOfAdvertisers),
        ("testAdvertiserDisposedAfterTimeoutWhenSecondAdvertiserStarts", AdvertiserManagerTests.testAdvertiserDisposedAfterTimeoutWhenSecondAdvertiserStarts),
        ("testStopAdvertising", AdvertiserManagerTests.testStopAdvertising),
      ]),
      testCase([
        ("testAdvertiserReturnsObjectWhenValidServiceType", AdvertiserTests.testAdvertiserReturnsObjectWhenValidServiceType),
        ("testAdvertiserReturnsNilWhenEmptyServiceType", AdvertiserTests.testAdvertiserReturnsNilWhenEmptyServiceType),
        ("testStartChangesAdvertisingState", AdvertiserTests.testStartChangesAdvertisingState),
        ("testStopWithoutCallingStartIsNOTError", AdvertiserTests.testStopWithoutCallingStartIsNOTError),
        ("testStopTwiceWithoutCallingStartIsNOTError", AdvertiserTests.testStopTwiceWithoutCallingStartIsNOTError),
        ("testStartTwiceChangesAdvertisingState", AdvertiserTests.testStartTwiceChangesAdvertisingState),
        ("testStartStopChangesAdvertisingState", AdvertiserTests.testStartStopChangesAdvertisingState),
        ("testStartStopStartChangesAdvertisingState", AdvertiserTests.testStartStopStartChangesAdvertisingState),
        ("testStopCalledTwiceChangesStateProperly", AdvertiserTests.testStopCalledTwiceChangesStateProperly),
        ("testStartAdvertisingErrorHandlerInvoked", AdvertiserTests.testStartAdvertisingErrorHandlerInvoked),
      ]),
      testCase([
        ("testStartListeningChangesListeningState", BrowserManagerTests.testStartListeningChangesListeningState),
        ("testStopListeningWithoutCallingStartIsNOTError", BrowserManagerTests.testStopListeningWithoutCallingStartIsNOTError),
        ("testStopListeningTwiceWithoutCallingStartIsNOTError", BrowserManagerTests.testStopListeningTwiceWithoutCallingStartIsNOTError),
        ("testStopListeningChangesListeningState", BrowserManagerTests.testStopListeningChangesListeningState),
        ("testStartStopStartListeningChangesListeningState", BrowserManagerTests.testStartStopStartListeningChangesListeningState),
        ("testStartListeningCalledTwiceChangesStateProperly", BrowserManagerTests.testStartListeningCalledTwiceChangesStateProperly),
        ("testStopListeningCalledTwiceChangesStateProperly", BrowserManagerTests.testStopListeningCalledTwiceChangesStateProperly),
        ("testConnectToPeerWithoutListeningReturnStartListeningNotActiveError", BrowserManagerTests.testConnectToPeerWithoutListeningReturnStartListeningNotActiveError),
        ("testConnectToWrongPeerReturnsIllegalPeerIDError", BrowserManagerTests.testConnectToWrongPeerReturnsIllegalPeerIDError),
        ("testPickLatestGenerationAdvertiserOnConnect", BrowserManagerTests.testPickLatestGenerationAdvertiserOnConnect),
        ("testReceivedPeerAvailabilityEventAfterFoundAdvertiser", BrowserManagerTests.testReceivedPeerAvailabilityEventAfterFoundAdvertiser),
        ("testIncrementAvailablePeersWhenFoundPeer", BrowserManagerTests.testIncrementAvailablePeersWhenFoundPeer),
        ("testPeerAvailabilityChangedAfterStartAdvertising", BrowserManagerTests.testPeerAvailabilityChangedAfterStartAdvertising),
        ("testPeerAvailabilityChangedAfterStopAdvertising", BrowserManagerTests.testPeerAvailabilityChangedAfterStopAdvertising),
        ("testConnectToPeerMethodReturnsTCPPort", BrowserManagerTests.testConnectToPeerMethodReturnsTCPPort),
      ]),
      testCase([
        ("testStartChangesListeningState", BrowserTests.testStartChangesListeningState),
        ("testStopWithoutCallingStartIsNOTError", BrowserTests.testStopWithoutCallingStartIsNOTError),
        ("testStopTwiceWithoutCallingStartIsNOTError", BrowserTests.testStopTwiceWithoutCallingStartIsNOTError),
        ("testStartStopChangesListeningState", BrowserTests.testStartStopChangesListeningState),
        ("testStartStopStartChangesListeningState", BrowserTests.testStartStopStartChangesListeningState),
        ("testStartListeningCalledTwiceChangesStateProperly", BrowserTests.testStartListeningCalledTwiceChangesStateProperly),
        ("testStopListeningCalledTwiceChangesStateProperly", BrowserTests.testStopListeningCalledTwiceChangesStateProperly),
        ("testFoundPeerHandlerCalled", BrowserTests.testFoundPeerHandlerCalled),
        ("testLostPeerHandlerCalled", BrowserTests.testLostPeerHandlerCalled),
        ("testStartListeningErrorHandlerCalled", BrowserTests.testStartListeningErrorHandlerCalled),
        ("testInviteToConnectPeerMethodReturnsSession", BrowserTests.testInviteToConnectPeerMethodReturnsSession),
        ("testInviteToConnectWrongPeerReturnsIllegalPeerIDError", BrowserTests.testInviteToConnectWrongPeerReturnsIllegalPeerIDError),
      ]),
      testCase([
        ("testMoveDataThrouhgRelayFromBrowserToAdvertiserUsingTCP", AdvertiserRelayTests.testMoveDataThrouhgRelayFromBrowserToAdvertiserUsingTCP),
      ]),
      testCase([
        ("testOpenRelayMethodReturnsTCPListenerPort", BrowserRelayTests.testOpenRelayMethodReturnsTCPListenerPort),
        ("testClientCanConnectToPortReturnedByRelay", BrowserRelayTests.testClientCanConnectToPortReturnedByRelay),
        ("testCloseRelayMethodOnBrowserClosesTCPListenerPort", BrowserRelayTests.testCloseRelayMethodOnBrowserClosesTCPListenerPort),
        ("testMoveDataThrouhgRelayFromAdvertiserToBrowserUsingTCP", BrowserRelayTests.testMoveDataThrouhgRelayFromAdvertiserToBrowserUsingTCP),
      ]),
      testCase([
        ("testOpenTenVirtualSocketsAndMoveData", RelayTests.testOpenTenVirtualSocketsAndMoveData),
      ]),
      testCase([
        ("testSessionStartsWithNotConnectedState", SessionTests.testSessionStartsWithNotConnectedState),
        ("testMCSessionDelegateMethodWithWhenConnectingParameterChangesState", SessionTests.testMCSessionDelegateMethodWithWhenConnectingParameterChangesState),
        ("testMCSessionDelegateMethodWithWhenConnectedParameterChangesState", SessionTests.testMCSessionDelegateMethodWithWhenConnectedParameterChangesState),
        ("testMCSessionDelegateMethodWithWhenNotConnectedParameterChangesState", SessionTests.testMCSessionDelegateMethodWithWhenNotConnectedParameterChangesState),
        ("testConnectHandlerInvokedWhenMCSessionStateChangesToConnected", SessionTests.testConnectHandlerInvokedWhenMCSessionStateChangesToConnected),
        ("testDisconnectHandlerInvokedWhenMCSessionStateChangesToDisconnected", SessionTests.testDisconnectHandlerInvokedWhenMCSessionStateChangesToDisconnected),
        ("testConnectAndDisconnectHandlersNotInvokedWhenMCSessionStateChangesToConnecting", SessionTests.testConnectAndDisconnectHandlersNotInvokedWhenMCSessionStateChangesToConnecting),
        ("testDidReceiveInputStreamHandlerInvokedWhenMCSessionDelegateReceiveInputStream", SessionTests.testDidReceiveInputStreamHandlerInvokedWhenMCSessionDelegateReceiveInputStream),
        ("testDidChangeStateHandlerInvokedWhenMCSessionStateChanges", SessionTests.testDidChangeStateHandlerInvokedWhenMCSessionStateChanges),
        ("testCreateOutputStreamMethodThrowsThaliCoreError", SessionTests.testCreateOutputStreamMethodThrowsThaliCoreError),
      ]),
      testCase([
        ("testTCPClientCanConnectToServerAndReturnsListenerPort", TCPClientTests.testTCPClientCanConnectToServerAndReturnsListenerPort),
        ("testReadDataHandlerInvokedWhenTCPClientGetsData", TCPClientTests.testReadDataHandlerInvokedWhenTCPClientGetsData),
        ("testDisconnectHandlerInvokedWhenServerDisconnects", TCPClientTests.testDisconnectHandlerInvokedWhenServerDisconnects),
      ]),
      testCase([
        ("testAcceptNewConnectionHandlerInvoked", TCPListenerTests.testAcceptNewConnectionHandlerInvoked),
        ("testReadDataHandlerInvoked", TCPListenerTests.testReadDataHandlerInvoked),
        ("testDisconnectHandlerInvoked", TCPListenerTests.testDisconnectHandlerInvoked),
        ("testTCPListenerCantListenOnBusyPortAndReturnsZeroPort", TCPListenerTests.testTCPListenerCantListenOnBusyPortAndReturnsZeroPort),
        ("testStopListeningForConnectionsReleasesPort", TCPListenerTests.testStopListeningForConnectionsReleasesPort),
        ("testStopListeningForConnectionsDisconnectsClient", TCPListenerTests.testStopListeningForConnectionsDisconnectsClient),
        ("testStopListeningForConnectionsCalledTwice", TCPListenerTests.testStopListeningForConnectionsCalledTwice),
      ]),
      testCase([
        ("testAdvertiserSocketBuilderCreatesVirtualSocket", VirtualSocketBuilderTests.testAdvertiserSocketBuilderCreatesVirtualSocket),
        ("testConnectionTimeoutErrorWhenBrowserSocketBuilderTimeout", VirtualSocketBuilderTests.testConnectionTimeoutErrorWhenBrowserSocketBuilderTimeout),
        ("testConnectionFailedErrorWhenBrowserSocketBuilderCantStartStream", VirtualSocketBuilderTests.testConnectionFailedErrorWhenBrowserSocketBuilderCantStartStream),
      ]),
      testCase([
        ("testVirtualSocketCreatedWithClosedState", VirtualSocketTests.testVirtualSocketCreatedWithClosedState),
        ("testVirtualSocketOpenStreamsChangesState", VirtualSocketTests.testVirtualSocketOpenStreamsChangesState),
        ("testVirtualSocketCloseStreams", VirtualSocketTests.testVirtualSocketCloseStreams),
        ("testOpenStreamsCalledTwiceChangesStateProperly", VirtualSocketTests.testOpenStreamsCalledTwiceChangesStateProperly),
        ("testCloseStreamsCalledTwiceChangesStateProperly", VirtualSocketTests.testCloseStreamsCalledTwiceChangesStateProperly),
      ]),
      testCase([
        ("testReturnsTrueWhenServiceTypeIsValid", StringRandomTests.testReturnsTrueWhenServiceTypeIsValid),
        ("testReturnsTrueWhenServiceTypeIsThaliproject", StringRandomTests.testReturnsTrueWhenServiceTypeIsThaliproject),
        ("testReturnsFalseWhenServiceTypeIsEmpty", StringRandomTests.testReturnsFalseWhenServiceTypeIsEmpty),
        ("testReturnsFalseWhenServiceTypeCharMoreThanMax", StringRandomTests.testReturnsFalseWhenServiceTypeCharMoreThanMax),
        ("testReturnsFalseWhenServiceTypeContainsNotPermittedCharacter", StringRandomTests.testReturnsFalseWhenServiceTypeContainsNotPermittedCharacter),
        ("testReturnsFalseWhenServiceTypeDoesNotContainAsLeastOneASCIICharacter", StringRandomTests.testReturnsFalseWhenServiceTypeDoesNotContainAsLeastOneASCIICharacter),
        ("testReturnsFalseWhenServiceTypeContainsHyphenFirst", StringRandomTests.testReturnsFalseWhenServiceTypeContainsHyphenFirst),
        ("testReturnsFalseWhenServiceTypeContainsHyphenLast", StringRandomTests.testReturnsFalseWhenServiceTypeContainsHyphenLast),
        ("testReturnsFalseWhenServiceTypeContainsAdjancesHyphens", StringRandomTests.testReturnsFalseWhenServiceTypeContainsAdjancesHyphens),
      ]),
    ]
  }
}
