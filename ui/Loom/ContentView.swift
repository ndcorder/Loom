//
//  ContentView.swift
//  Loom
//
//  Two-pane skeleton: left = call tree (color-coded nodes),
//  right = detail with segmented Prompt / Response tabs.
//

import SwiftUI

struct ContentView: View {
    private let calls = CallNode.sample
    @State private var selectedID: CallNode.ID?

    var body: some View {
        NavigationSplitView {
            List(calls, selection: $selectedID) { call in
                CallRow(call: call)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .navigationTitle("Calls")
        } detail: {
            if let id = selectedID, let call = calls.first(where: { $0.id == id }) {
                CallDetail(call: call)
            } else {
                ContentUnavailableView(
                    "Select a call",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Pick a node from the tree to inspect its prompt and response.")
                )
            }
        }
    }
}

/// A single row in the call list: status dot + step + model + time.
struct CallRow: View {
    let call: CallNode

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(call.status.color)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(call.step)
                Text(call.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(call.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Detail pane: status header + segmented Prompt/Response tabs (monospaced, scrollable).
struct CallDetail: View {
    let call: CallNode
    @State private var tab: Tab = .prompt

    enum Tab: String, CaseIterable, Identifiable {
        case prompt = "Prompt"
        case response = "Response"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            ScrollView {
                Text(tab == .prompt ? call.prompt : call.response)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .navigationTitle(call.step)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(call.status.color)
                .frame(width: 10, height: 10)
            Text(call.status.label)
                .font(.headline)
                .foregroundStyle(call.status.color)
            Text(call.model)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if let tokens = call.tokens {
                Label("\(tokens) tok", systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(call.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
