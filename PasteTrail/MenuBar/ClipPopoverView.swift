// PasteTrail/MenuBar/ClipPopoverView.swift
import SwiftUI

struct ClipPopoverView: View {
    @EnvironmentObject var clipStore: ClipStore
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Text("Paste Trail")
            .frame(width: 380, height: 100)
    }
}
