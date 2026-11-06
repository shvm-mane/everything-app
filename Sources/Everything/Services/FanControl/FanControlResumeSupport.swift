// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

extension FanControlConfiguration {
    static func encodeResume(_ configuration: FanControlConfiguration) -> String? {
        guard configuration.mode != .system,
              FanControlPolicy.validConfiguration(configuration) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(configuration) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodeResume(_ value: String) -> FanControlConfiguration? {
        guard let data = value.data(using: .utf8),
              let configuration = try? JSONDecoder().decode(FanControlConfiguration.self, from: data),
              configuration.mode != .system,
              FanControlPolicy.validConfiguration(configuration) else { return nil }
        return configuration
    }
}
