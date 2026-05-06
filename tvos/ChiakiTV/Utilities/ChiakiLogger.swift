// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import OSLog

/// Unified logging surface for ChiakiTV.
///
/// In Phase 1 this will also be the destination for log lines that flow up
/// from chiaki-lib via the `ChiakiLog` callback registered through the
/// bridge — so a single timestamped stream covers Swift services and the
/// upstream C protocol layer.
enum LogCategory: String {
    case network
    case video
    case audio
    case controller
    case session
    case bridge
    case ui
}

@inline(__always)
func chiakiLog(
    _ message: String,
    category: LogCategory = .session,
    type: OSLogType = .default
) {
    let logger = Logger(subsystem: "org.streetpea.chiakitv", category: category.rawValue)
    logger.log(level: type, "\(message, privacy: .public)")
}
