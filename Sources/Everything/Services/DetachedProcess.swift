// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum DetachedProcess {
    @discardableResult
    static func spawn(_ executablePath: String, _ arguments: [String]) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes,
                                 Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 2, "/dev/null", O_WRONLY, 0)

        let argv: [UnsafeMutablePointer<CChar>?] =
            ([executablePath] + arguments).map { strdup($0) } + [nil]
        defer { for argument in argv { free(argument) } }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, executablePath, &fileActions, &attributes, argv, environ)
        guard status == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(status))])
        }
        return pid
    }

    static func detachedShellCommand(quotedArgv: String) -> String {
        let setsid = "/usr/bin/perl -e 'use POSIX (); "
            + "POSIX::setsid(); $SIG{HUP} = \"IGNORE\"; exec @ARGV; exit 127'"
        return "set -- \(quotedArgv); { if [ -x /usr/bin/perl ]; then exec \(setsid) \"$@\"; "
            + "else exec /usr/bin/nohup \"$@\"; fi; } >/dev/null 2>&1 &"
    }
}
