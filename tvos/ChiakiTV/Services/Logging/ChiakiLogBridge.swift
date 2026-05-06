// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import OSLog
import ChiakiBridgeC

/// Funnels chiaki-lib log lines through OSLog so they show up alongside our
/// own Swift log lines under `subsystem=org.streetpea.chiakitv`,
/// `category=bridge`.
///
/// Install once at app launch via `install()`. The bridge holds a static
/// trampoline; no instance state.
enum ChiakiLogBridge {

    private static let cCallback: @convention(c) (
        Int32, UnsafePointer<CChar>?, UnsafeMutableRawPointer?
    ) -> Void = { level, msgPtr, _ in
        guard let msgPtr = msgPtr else { return }
        let line = String(cString: msgPtr)
        let type = mapLogLevel(level)
        chiakiLog(line, category: .bridge, type: type)
    }

    private static func mapLogLevel(_ level: Int32) -> OSLogType {
        switch level {
        case Int32(CHIAKI_TV_LOG_ERROR.rawValue):   return .error
        case Int32(CHIAKI_TV_LOG_WARNING.rawValue): return .default
        case Int32(CHIAKI_TV_LOG_INFO.rawValue):    return .info
        case Int32(CHIAKI_TV_LOG_DEBUG.rawValue):   return .debug
        case Int32(CHIAKI_TV_LOG_VERBOSE.rawValue): return .debug
        default:                                    return .debug
        }
    }

    static func install() {
        chiaki_tv_log_set_callback(cCallback, nil)
        chiakiLog("ChiakiLogBridge: installed", category: .bridge, type: .info)
    }
}
