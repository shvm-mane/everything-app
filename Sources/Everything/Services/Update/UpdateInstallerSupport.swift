// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum UpdateInstallerSupport {
    static func installFailureCode(fromMarker marker: String) -> String? {
        let trimmed = marker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("fail") else { return nil }
        return trimmed
    }

    static func installerScript() -> String {
        """
        #!/bin/sh
        APP="$1"; DMG="$2"; PID="$3"; RESULT="$4"; ASUSER="$5"; EXPECTED_VERSION="$6"
        SCRIPT="$0"
        # Write-ahead markers go to a progress file; only a FINISHED run
        # promotes it to the real marker. The app may relaunch while this
        # script is still mid-install, and a transient step must not be
        # reported as a failure.
        running_as_root() { [ "$(/usr/bin/id -u)" = "0" ]; }
        note() {
            if running_as_root; then
                [ -n "$ASUSER" ] || return 1
                # The marker directory belongs to the user. Drop privileges
                # before opening it so a replaced path cannot make root follow
                # a symlink while the administrator prompt is on screen.
                /usr/bin/sudo -n -u "#$ASUSER" /bin/sh -c \
                    '/bin/echo "$1" > "$2.progress"' marker "$1" "$RESULT" 2>/dev/null
                return
            fi
            /bin/echo "$1" > "$RESULT.progress" 2>/dev/null
        }
        finalize() {
            if running_as_root; then
                [ -n "$ASUSER" ] || return 1
                /usr/bin/sudo -n -u "#$ASUSER" /bin/mv -f \
                    "$RESULT.progress" "$RESULT" 2>/dev/null
                return
            fi
            /bin/mv -f "$RESULT.progress" "$RESULT" 2>/dev/null
        }
        cleanup_script() { case "$SCRIPT" in /*) /bin/rm -f "$SCRIPT";; esac; }
        relaunch() {
            if [ -n "$ASUSER" ] && [ "$(/usr/bin/id -u)" = "0" ]; then
                /bin/launchctl asuser "$ASUSER" /usr/bin/open "$1" && return
            fi
            /usr/bin/open "$1"
        }
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        note fail-dmg-verify
        DMG_VERIFY_REQ='anchor apple generic and certificate leaf[subject.OU] = "3D485NHW29"'
        if ! /usr/bin/codesign -v --strict -R="$DMG_VERIFY_REQ" "$DMG" 2>/dev/null; then
            /bin/rm -f "$DMG"
            finalize
            relaunch "$APP"
            cleanup_script
            exit 1
        fi
        note fail-tempdir
        MNT="$(/usr/bin/mktemp -d)" || { /bin/rm -f "$DMG"; finalize; relaunch "$APP"; cleanup_script; exit 1; }
        note fail-mount
        if ! /usr/bin/hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MNT"; then
            /bin/rmdir "$MNT" 2>/dev/null
            /bin/rm -f "$DMG"
            finalize
            relaunch "$APP"
            cleanup_script
            exit 1
        fi
        SRC="$(/usr/bin/find "$MNT" -maxdepth 1 -name '*.app' -print -quit)"
        LAUNCH="$APP"
        if [ -z "$SRC" ]; then
            note fail-no-app-in-dmg
        else
            # Install under the name the DMG ships, in the same folder. A rebrand
            # changes the bundle filename, so this renames it on disk too; a plain
            # update keeps the same name and replaces it in place.
            DIR="$(/usr/bin/dirname "$APP")"
            NAME="$(/usr/bin/basename "$SRC")"
            DEST="$DIR/$NAME"
            # Stage the full copy FIRST; the old app is only removed after the
            # copy completed, so a failure mid-copy never leaves the user with no
            # app at all. The staging name is hidden: Spotlight recognizes the
            # copy as an app bundle whatever its suffix, and when the swap lands
            # while that copy is still being indexed, the installed app keeps
            # showing up in search as "Vorssaint.app.update-new".
            STAGE="$DIR/.$NAME.update-new"
            # A copy an earlier build left behind under the visible name is the
            # same leftover, still indexed; it goes with this one.
            /bin/rm -rf "$STAGE" "$DEST.update-new"
            note fail-copy
            if /usr/bin/ditto "$SRC" "$STAGE"; then
                # Clear ALL xattrs (quarantine + FinderInfo the DMG round-trip
                # adds): FinderInfo breaks strict signature verification.
                /usr/bin/xattr -cr "$STAGE" 2>/dev/null
                note fail-version
                BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$STAGE/Contents/Info.plist" 2>/dev/null)"
                if [ "$BUNDLE_VERSION" = "$EXPECTED_VERSION" ]; then
                    # When the user disabled Gatekeeper, spctl cannot assess anything
                    # and rejects even a healthy bundle; the codesign identity check
                    # below stays as the gate in that case.
                    GATEKEEPER_OK=0
                    if /usr/sbin/spctl --status 2>/dev/null | /usr/bin/grep -q disabled; then
                        GATEKEEPER_OK=1
                    elif /usr/sbin/spctl -a -t exec "$STAGE" >/dev/null 2>&1; then
                        GATEKEEPER_OK=1
                    fi
                    VERIFY_REQ='identifier "com.vorssaint.utils" and anchor apple generic and certificate leaf[subject.OU] = "3D485NHW29"'
                    note fail-verify
                    if /usr/bin/codesign -v --deep --strict -R="$VERIFY_REQ" "$STAGE" 2>/dev/null \
                        && [ "$GATEKEEPER_OK" = 1 ]; then
                        note fail-swap
                        # The backup name is unique per run: after an elevated
                        # install the old bundle is root-owned, a later user-run
                        # cannot delete that backup, and reusing a fixed name
                        # would make the NEXT swap fail on it. Strays from
                        # earlier runs are swept best-effort (an elevated run
                        # clears even the root-owned ones).
                        BACKUP="$DEST.update-old.$PID"
                        /bin/rm -rf "$DEST".update-old "$DEST".update-old.* 2>/dev/null
                        if { [ ! -d "$DEST" ] || /bin/mv "$DEST" "$BACKUP"; } \
                            && /bin/mv "$STAGE" "$DEST"; then
                            LAUNCH="$DEST"
                            note ok
                            # Installed as root: hand the bundle to the user, or
                            # the next user-path update cannot replace it.
                            if [ "$(/usr/bin/id -u)" = "0" ] && [ -n "$ASUSER" ]; then
                                /usr/sbin/chown -R "$ASUSER" "$DEST" 2>/dev/null
                            fi
                            /bin/rm -rf "$BACKUP"
                            # If the bundle was renamed, remove the old-named one.
                            # This happens only after the new bundle is in place.
                            [ "$DEST" != "$APP" ] && /bin/rm -rf "$APP"
                        else
                            [ -d "$BACKUP" ] && [ ! -d "$DEST" ] && /bin/mv "$BACKUP" "$DEST"
                        fi
                    fi
                fi
            fi
            /bin/rm -rf "$STAGE"
        fi
        /usr/bin/hdiutil detach "$MNT" -quiet 2>/dev/null \
            || /usr/bin/hdiutil detach "$MNT" -force -quiet 2>/dev/null \
            || true
        /bin/rmdir "$MNT" 2>/dev/null
        /bin/rm -f "$DMG"
        finalize
        relaunch "$LAUNCH"
        cleanup_script
        """
    }

    static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func elevatedInstallCommand(appPath: String,
                                       dmgPath: String,
                                       pid: Int32,
                                       resultPath: String,
                                       uid: uid_t,
                                       expectedVersion: String) -> String {
        let script = shellSingleQuoted(installerScript())
        let args = [appPath, dmgPath, "\(pid)", resultPath, "\(uid)", expectedVersion]
            .map(shellSingleQuoted)
            .joined(separator: " ")
        return DetachedProcess.detachedShellCommand(
            quotedArgv: "/bin/sh -c \(script) vorssaint-installer \(args)")
    }

    static func shouldForceAdminInstall(afterFailureCode code: String?) -> Bool {
        code == "fail-copy" || code == "fail-swap"
    }

    static func progressStepAdvanced(from current: Double?, to fraction: Double) -> Bool {
        guard let current else { return true }
        return Int(fraction * 100) > Int(current * 100)
    }

    static let downloadCeilingBytes: Int64 = 200 * 1024 * 1024

    static func downloadByteLimit(expectedBytes: Int64?,
                                  ceiling: Int64 = downloadCeilingBytes) -> Int64 {
        guard let expectedBytes, expectedBytes > 0, expectedBytes <= ceiling else {
            return ceiling
        }
        return expectedBytes
    }

    static func downloadIsUsable(status: Int,
                                 receivedBytes: Int64,
                                 expectedBytes: Int64?,
                                 ceiling: Int64 = downloadCeilingBytes) -> Bool {
        guard status == 200, receivedBytes > 0, receivedBytes <= ceiling else { return false }
        guard let expectedBytes, expectedBytes > 0 else { return true }
        return receivedBytes == expectedBytes
    }

    static func runsFromImmutableLocation(appPath: String,
                                          volumeIsReadOnly: (String) -> Bool) -> Bool {
        appPath.contains("/AppTranslocation/") || volumeIsReadOnly(appPath)
    }
}
