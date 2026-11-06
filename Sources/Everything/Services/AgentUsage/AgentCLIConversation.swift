// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

class AgentCLIConversation {
    private static let maximumBuffer = 4 << 20

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let deadline: DispatchTime
    private let cancellation: BoundedProcessCancellation?
    private let arrived = DispatchSemaphore(value: 0)
    private let exited = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var buffer = Data()
    private var closed = false

    init?(_ executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval,
          cancellation: BoundedProcessCancellation? = nil) {
        self.cancellation = cancellation
        deadline = .now() + timeout
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { return nil }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil }
            self?.receive(chunk)
        }
        process.terminationHandler = { [exited] _ in exited.signal() }
        do {
            if let cancellation { try cancellation.launch(process) } else { try process.run() }
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
    }

    func end() {
        try? input.fileHandleForWriting.close()
        let child = process
        if let cancellation {
            let leaves = ProcessInfo.processInfo.systemUptime + 0.3
            while child.isRunning, ProcessInfo.processInfo.systemUptime < leaves { usleep(10_000) }
            if child.isRunning { child.terminate() }
            let stops = ProcessInfo.processInfo.systemUptime + 0.5
            while child.isRunning, ProcessInfo.processInfo.systemUptime < stops { usleep(10_000) }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            output.fileHandleForReading.readabilityHandler = nil
            cancellation.release(child)
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            guard child.isRunning else { return }
            child.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
    }

    @discardableResult func waitForExit(timeout: TimeInterval) -> Bool {
        exited.wait(timeout: .now() + timeout) == .success
    }

    func send(_ message: [String: Any]) -> Bool {
        if let cancellation, cancellation.isCancelled || DispatchTime.now() >= deadline { return false }
        guard JSONSerialization.isValidJSONObject(message),
              var line = try? JSONSerialization.data(withJSONObject: message, options: .withoutEscapingSlashes)
        else { return false }
        line.append(0x0A)
        do {
            try input.fileHandleForWriting.write(contentsOf: line)
            return true
        } catch {
            return false
        }
    }

    private func receive(_ chunk: Data) {
        lock.withLock {
            if chunk.isEmpty || buffer.count + chunk.count > Self.maximumBuffer { closed = true }
            else { buffer.append(chunk) }
        }
        arrived.signal()
    }

    func next() -> [String: Any]? {
        while true {
            if let cancellation, cancellation.isCancelled || DispatchTime.now() >= deadline { return nil }
            let (line, ended): (Data?, Bool) = lock.withLock {
                guard let newline = buffer.firstIndex(of: 0x0A) else { return (nil, closed) }
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                return (line, false)
            }
            if let line {
                if let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] { return message }
                continue
            }
            if ended { return nil }
            if cancellation != nil {
                _ = arrived.wait(timeout: min(deadline, .now() + 0.1))
            } else if arrived.wait(timeout: deadline) == .timedOut { return nil }
        }
    }
}
