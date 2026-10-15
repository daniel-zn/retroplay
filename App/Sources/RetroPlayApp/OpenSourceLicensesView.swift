// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// One entry in the bundled `Licenses/components.json`.
struct OpenSourceComponent: Decodable, Identifiable, Hashable {
    let name: String
    /// Which part of RetroPlay uses it (e.g. "PSP core (PPSSPP)").
    let usedBy: String
    let license: String
    let copyright: String
    let source: String
    /// Revision or version shipped, when known.
    let version: String?
    /// File name inside `Licenses/` holding the full license text.
    let licenseFile: String

    var id: String { "\(usedBy)/\(name)/\(licenseFile)" }
}

/// Settings → Open Source Licenses: RetroPlay's own GPL notice, where to get the source,
/// and every bundled component with its copyright line and full license text.
@available(iOS 18.0, *)
struct OpenSourceLicensesView: View {
    /// Public source for RetroPlay and its patches; each release is tagged with its version.
    static let sourceURL = URL(string: "https://github.com/daniel-zn/retroplay")!

    @Environment(\.colorScheme) private var colorScheme
    private let components = Self.loadComponents()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RetroPlay")
                        .font(RetroPlayFont.body)
                    Text(Self.appNotice)
                        .font(RetroPlayFont.caption2)
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                Link(destination: Self.sourceURL) {
                    SettingsIconLabel("Source Code", symbol: "chevron.left.forwardslash.chevron.right", color: .indigo)
                }
                NavigationLink {
                    LicenseTextView(title: "GPL-3.0", fileName: "GPL-3.0.txt")
                } label: {
                    SettingsIconLabel("GNU GPL v3", symbol: "doc.text.fill", color: .gray)
                }
            } header: {
                header("RetroPlay")
            }
            .listRowBackground(RetroPlayTheme.card(for: colorScheme))

            ForEach(groupedComponents, id: \.0) { group, items in
                Section {
                    ForEach(items) { component in
                        NavigationLink {
                            ComponentLicenseView(component: component)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(component.name)
                                    .font(RetroPlayFont.caption)
                                Text(component.license)
                                    .font(RetroPlayFont.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    header(group)
                }
                .listRowBackground(RetroPlayTheme.card(for: colorScheme))
            }
        }
        .scrollContentBackground(.hidden)
        .background(RetroPlayTheme.canvas(for: colorScheme))
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }

    static let appNotice = """
        Copyright © 2026 The RetroPlay Authors. RetroPlay is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3 or (at your option) any later version.

        RetroPlay comes with ABSOLUTELY NO WARRANTY; see the GNU General Public License for details.

        The complete source code for this version of RetroPlay, including the exact emulator-core revisions and RetroPlay's patches to them, is available at the Source Code link below.
        """

    private var groupedComponents: [(String, [OpenSourceComponent])] {
        var order: [String] = []
        var groups: [String: [OpenSourceComponent]] = [:]
        for component in components {
            if groups[component.usedBy] == nil { order.append(component.usedBy) }
            groups[component.usedBy, default: []].append(component)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(RetroPlayFont.caption2)
            .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
    }

    static func licensesURL(_ fileName: String) -> URL? {
        Bundle.main.url(forResource: "Licenses", withExtension: nil)?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func loadComponents() -> [OpenSourceComponent] {
        guard let url = licensesURL("components.json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([OpenSourceComponent].self, from: data)
        else { return [] }
        return list
    }
}

@available(iOS 18.0, *)
private struct ComponentLicenseView: View {
    let component: OpenSourceComponent
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            Section {
                row("Used by", component.usedBy)
                row("License", component.license)
                if let version = component.version {
                    stacked("Version", version)
                }
                stacked("Copyright", component.copyright)
                if let url = URL(string: component.source) {
                    Link(destination: url) {
                        SettingsIconLabel("Source", symbol: "link", color: .indigo)
                    }
                }
                NavigationLink {
                    LicenseTextView(title: component.license, fileName: component.licenseFile)
                } label: {
                    SettingsIconLabel("License Text", symbol: "doc.text.fill", color: .gray)
                }
            }
            .listRowBackground(RetroPlayTheme.card(for: colorScheme))
        }
        .scrollContentBackground(.hidden)
        .background(RetroPlayTheme.canvas(for: colorScheme))
        .navigationTitle(component.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Label above value, for long values (commit hashes, copyright lines).
    private func stacked(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(RetroPlayFont.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(RetroPlayFont.caption2)
                .textSelection(.enabled)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .font(RetroPlayFont.caption2)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(title)
                .font(RetroPlayFont.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// Full license text, in the system monospaced face: legal text must stay readable,
/// and the app's display font makes long passages hard to read.
@available(iOS 18.0, *)
private struct LicenseTextView: View {
    let title: String
    let fileName: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(RetroPlayTheme.canvas(for: colorScheme))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var text: String {
        guard let url = OpenSourceLicensesView.licensesURL(fileName),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "License text missing from this build: \(fileName)" }
        return text
    }
}
