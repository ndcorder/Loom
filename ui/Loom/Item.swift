//
//  Item.swift
//  Loom
//
//  Day-1 data model for the call tree. In-memory only (no SwiftData/SQLite yet).
//  Filename kept as-is so the Xcode project reference stays valid.
//

import SwiftUI

/// Outcome of a single intercepted LLM call → drives the node color in the UI.
enum CallStatus: String, Hashable {
    case live    // 🟢 forwarded live, valid response
    case cached  // 🟡 served from local cache (0 ms, $0)
    case error   // 🔴 failed (no balance, network down, invalid JSON, ...)

    var color: Color {
        switch self {
        case .live: .green
        case .cached: .yellow
        case .error: .red
        }
    }

    var label: String {
        switch self {
        case .live: "Live"
        case .cached: "Cached"
        case .error: "Error"
        }
    }
}

/// One node in the agent's call tree.
struct CallNode: Identifiable, Hashable {
    let id = UUID()
    var step: String
    var model: String
    var status: CallStatus
    var timestamp: Date
    var prompt: String
    var response: String
    var tokens: Int?
}

extension CallNode {
    /// Hardcoded fake steps to exercise the interface on Day 1.
    static let sample: [CallNode] = [
        CallNode(
            step: "1 · Plan task",
            model: "claude-opus-4-8",
            status: .live,
            timestamp: Date().addingTimeInterval(-180),
            prompt: """
            System: You are an autonomous coding agent.
            User: Build a small CSV parser in Rust with tests.
            """,
            response: """
            I'll scaffold a `csv` module, implement a streaming line splitter,
            then add unit tests for quoted fields and embedded commas.
            """,
            tokens: 420
        ),
        CallNode(
            step: "2 · Read project files",
            model: "claude-opus-4-8",
            status: .cached,
            timestamp: Date().addingTimeInterval(-120),
            prompt: """
            Tool result: Cargo.toml + src/main.rs contents attached.
            What is the next step?
            """,
            response: """
            (served from local cache — 0 ms, $0)
            Next: create src/csv.rs and expose `parse_line`.
            """,
            tokens: 0
        ),
        CallNode(
            step: "3 · Generate JSON patch",
            model: "gpt-5.5",
            status: .error,
            timestamp: Date().addingTimeInterval(-30),
            prompt: """
            Return ONLY valid JSON: {"file": string, "code": string}.
            """,
            response: """
            ERROR: model returned invalid JSON —
            unterminated string literal at line 12. Agent could not parse the patch.
            """,
            tokens: nil
        ),
    ]
}
