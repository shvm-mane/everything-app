// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct PortManagerFeatureStrings {
    let title: String
    let filter: String
    let openFormat: String
    let empty: String
    let emptyHint: String
    let listeningCaption: String
    let kill: String
    let forceKill: String
    let loadFailed: String
    let refresh: String
    let copyPort: String
    let copyAddress: String
    let terminateFormat: String
    let terminateMessageFormat: String
    let hubDescription: String
    let allInterfaces: String
    let allInterfacesHelp: String
}

extension FeatureStrings {
    static func portManager(_ language: AppLanguage) -> PortManagerFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension PortManagerFeatureStrings {

    static let enUS = PortManagerFeatureStrings(title: "Port Manager", filter: "Filter by port, process, or PID", openFormat: "%d open", empty: "No listening ports found", emptyHint: "Try refreshing or changing your search.", listeningCaption: "Your listening ports", kill: "Kill", forceKill: "Force Kill", loadFailed: "Could not read listening ports. Try refreshing.", refresh: "Refresh", copyPort: "Copy port", copyAddress: "Copy address:port", terminateFormat: "Terminate %@?", terminateMessageFormat: "This closes port %d by terminating PID %d.", hubDescription: "View active listening ports and, with Kill Process installed, terminate the processes using them", allInterfaces: "All interfaces", allInterfacesHelp: "Listening on every network interface, so other devices on the network may be able to connect.")
}
