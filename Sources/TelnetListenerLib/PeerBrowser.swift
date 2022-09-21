/*
Based on Apple sample code: https://developer.apple.com/documentation/network/building_a_custom_peer-to-peer_protocol

Abstract:
Create a class to browse for game peers using Bonjour.
*/

import Foundation
import Network
import os

var sharedBrowser: PeerBrowser?

// Update the UI when you receive new browser results.
protocol PeerBrowserDelegate: AnyObject {
	func refreshResults(results: Set<NWBrowser.Result>)
	func displayBrowseError(_ error: NWError)
}

/// The name of the target service. Can be overriddentbefore calling `startBrowsing`.
public var targetService = "_openlcb-can._tcp"

/// Browse for Bonjour/mDNS peers
public class PeerBrowser {

	var delegate: PeerBrowserDelegate?
	var browser: NWBrowser?
                                      
	// Create a browsing object with a delegate.
	init(delegate: PeerBrowserDelegate) {
		self.delegate = delegate
		startBrowsing()
	}

    private static let logger = Logger(subsystem: "us.ardenwood.TelnetListenerLib", category: "PeerBrowser")

	// Start browsing for services.
	func startBrowsing() {
		// Create parameters, and allow browsing over a peer-to-peer link.
		let parameters = NWParameters()
		parameters.includePeerToPeer = true

		// Browse for the target service type
		let browser = NWBrowser(for: .bonjour(type: targetService, domain: nil), using: parameters)
		self.browser = browser
		browser.stateUpdateHandler = { newState in
			switch newState {
			case .failed(let error):
				// Restart the browser if it loses its connection.
				if error == NWError.dns(DNSServiceErrorType(kDNSServiceErr_DefunctConnection)) {
                    PeerBrowser.logger.warning("Browser failed with \(error.debugDescription), restarting")
					browser.cancel()
					self.startBrowsing()
				} else {
                    PeerBrowser.logger.warning("Browser failed with \(error.debugDescription), stopping")
					self.delegate?.displayBrowseError(error)
					browser.cancel()
				}
			case .ready:
				// Post initial results.
				self.delegate?.refreshResults(results: browser.browseResults)
			case .cancelled:
				sharedBrowser = nil
				self.delegate?.refreshResults(results: Set())
			default:
				break
			}
		}

		// When the list of discovered endpoints changes, refresh the delegate.
		browser.browseResultsChangedHandler = { results, changes in
			self.delegate?.refreshResults(results: results)
		}

		// Start browsing and ask for updates on the main queue.
		browser.start(queue: .main)
	}
}
