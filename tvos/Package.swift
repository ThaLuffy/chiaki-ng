// swift-tools-version: 5.9
// SPDX-License-Identifier: AGPL-3.0-only
//
// SPM manifest for ChiakiTV's headless test runner.
//
// XcodeGen + Xcode is the front door for the full tvOS app (it can build the
// VideoToolbox / Metal / GameController surface). This manifest exists so the
// C bridge can be unit-tested headlessly via `swift test` without spinning up
// a tvOS simulator.
//
// Bridge sources split into two categories:
//   - Standalone (`chiaki_bridge.c`): version-string stubs that don't touch
//     chiaki-lib. Build under SPM on macOS.
//   - Lib-touching (`chiaki_bridge_lib.c`, `chiaki_bridge_discovery.c`,
//     future ones): include `<chiaki/...>` headers from
//     `Vendors/prefix/<slice>/include/` and link against libchiaki.a + its
//     deps. Those slices are tvOS-only, so the SPM target excludes them and
//     they're built only via XcodeGen + Xcode.
// Tests that exercise lib-touching bridge code live in the Xcode-only
// ChiakiTVTests target (see Tests/ChiakiTVTests/).

import PackageDescription

let package = Package(
    name: "ChiakiTV",
    platforms: [
        .tvOS(.v17),
        .macOS(.v14),  // For running C bridge tests on the dev machine.
    ],
    products: [
        .library(
            name: "ChiakiBridgeC",
            targets: ["ChiakiBridgeC"]
        ),
    ],
    targets: [
        // C bridge: thin Swift ↔ chiaki-lib glue.
        // SPM excludes the chiaki-lib-touching files (they need the tvOS-only
        // slice headers + lib link). Xcode builds the full set; see the
        // header comment for the split.
        .target(
            name: "ChiakiBridgeC",
            path: "ChiakiBridgeC",
            exclude: [
                "src/chiaki_bridge_lib.c",
                "src/chiaki_bridge_discovery.c",
                "src/chiaki_bridge_log.c",
                "src/chiaki_bridge_regist.c",
                "src/chiaki_bridge_session.c",
            ],
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
            ]
        ),

        // C bridge tests.
        .testTarget(
            name: "ChiakiBridgeCTests",
            dependencies: ["ChiakiBridgeC"],
            path: "Tests/ChiakiBridgeCTests"
        ),
    ]
)
