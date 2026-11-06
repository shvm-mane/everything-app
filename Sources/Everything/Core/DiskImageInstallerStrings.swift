// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DiskImageInstallerStrings {
    let title: String
    let hubDescription: String
    let useUserApplications: String
    let applicationsFolder: String
    let userApplicationsFolder: String
    let promptTitle: String
    let promptBodyFormat: String
    let installButton: String
    let installedTitle: String
    let installedBodyFormat: String
    let installedKeepingMountBodyFormat: String
    let installedKeepingDownloadBodyFormat: String
    let failedTitle: String
    let failedBody: String
    let verificationFailedBody: String
    let alreadyInstalledBodyFormat: String
    let trashDownloadOption: String
    let revealAppOption: String
    let installedKeptDownloadBodyFormat: String
    let installingFormat: String
}

extension FeatureStrings {
    static func diskImageInstaller(_ language: AppLanguage) -> DiskImageInstallerStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension DiskImageInstallerStrings {
    static let enUS = DiskImageInstallerStrings(
        title: "Disk image installer",
        hubDescription: "Install the single app inside a disk image and clean up the download",
        useUserApplications: "Install in the Applications folder inside your home folder",
        applicationsFolder: "the Applications folder",
        userApplicationsFolder: "the Applications folder inside your home folder",
        promptTitle: "Install this app?",
        promptBodyFormat: "%@ will be copied to %@ and the disk image ejected.",
        installButton: "Install",
        installedTitle: "App installed",
        installedBodyFormat: "%@ is ready in %@. The disk image was ejected and its download moved to Trash.",
        installedKeepingMountBodyFormat: "%@ is installed in %@, but the disk image could not be ejected. Its download was kept.",
        installedKeepingDownloadBodyFormat: "%@ is installed in %@ and the disk image was ejected, but its download could not be moved to Trash.",
        failedTitle: "Could not install",
        failedBody: "Nothing was changed. You can still drag the app to Applications.",
        verificationFailedBody: "This Mac could not verify the app, so nothing was installed.",
        alreadyInstalledBodyFormat: "%@ is already in Applications.",
        trashDownloadOption: "Move the download to Trash",
        revealAppOption: "Show the installed app in Finder",
        installedKeptDownloadBodyFormat: "%@ is ready in %@. The disk image was ejected and its download kept.",
        installingFormat: "Installing %@…"
    )

}
