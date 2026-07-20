// Targie - Find similar videos on macOS.
// Copyright (C) 2026 Lirui Yu
//
// This file is part of Targie.
//
// Targie is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Targie is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Targie.  If not, see <https://www.gnu.org/licenses/>.
//
// If you reuse this code (modified or not), you must keep this notice
// and credit the original author (Lirui Yu).

import SwiftUI

/// Consolidated settings popover reached from the main toolbar's Settings
/// button. Hosts the infrequent controls that used to be direct toolbar
/// buttons: Deep Verification (video Vision frame verification), Scan
/// Intensity, Language, and Clear Cache. The Settings button stays enabled
/// during a scan so Language remains reachable; the per-item disabled states
/// mirror what each control had when it lived directly in the toolbar.
struct SettingsPopover: View {
    @ObservedObject var model: ScanViewModel
    @Binding var scanIntensityRawValue: String
    @Binding var languageRawValue: String
    @Binding var deepVerification: Bool
    var onClearCache: () -> Void

    @Environment(\.appLanguage) private var language

    private var scanIntensity: ScanIntensity {
        ScanIntensity(rawValue: scanIntensityRawValue) ?? .defaultIntensity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            deepVerificationSection
            Divider()
            intensitySection
            Divider()
            languageSection
            Divider()
            clearCacheSection
        }
        .padding(16)
        .frame(width: 280)
    }

    // MARK: - Deep Verification

    private var deepVerificationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $deepVerification) {
                Text(L10n.deepVerification(language))
                    .font(.headline)
            }
            .toggleStyle(.checkbox)
            .disabled(model.isBusy)

            Text(L10n.deepVerificationHelp(language))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Scan Intensity

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.scanIntensity(language)).font(.headline)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ScanIntensity.allCases) { option in
                    Button {
                        scanIntensityRawValue = option.rawValue
                        model.setScanIntensity(option)
                    } label: {
                        selectionRow(
                            label: L10n.scanIntensityName(option, language),
                            isSelected: option == scanIntensity
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isBusy)
                }
            }
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.language(language)).font(.headline)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(AppLanguage.allCases) { option in
                    Button {
                        languageRawValue = option.rawValue
                    } label: {
                        selectionRow(
                            label: option.menuLabel,
                            isSelected: option == language
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Clear Cache

    private var clearCacheSection: some View {
        Button {
            onClearCache()
        } label: {
            Label(L10n.clearCache(language), systemImage: "arrow.triangle.2.circlepath")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(model.isBusy)
    }

    // MARK: - Row

    @ViewBuilder
    private func selectionRow(label: String, isSelected: Bool) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 16)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
