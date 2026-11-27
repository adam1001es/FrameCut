import SwiftUI

struct ExportSheet: View {
    @EnvironmentObject private var model: EditorModel
    @StateObject private var exporter = Exporter()
    @State private var quality: ExportQuality = .hevc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Projekt") {
                    infoRow("Auflösung", model.state.renderSize.resolutionLabel)
                    infoRow("Bildrate", "\(Int(model.state.frameRate.rounded())) fps")
                    infoRow("Dynamik", model.state.isHDR ? "HDR (HLG / Dolby Vision)" : "SDR")
                    infoRow("Länge", model.state.totalDuration.timecode)
                }

                Section {
                    ForEach(ExportQuality.allCases) { option in
                        let blocker = blocker(for: option)
                        Button { quality = option } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.title).font(.headline)
                                    Text(blocker ?? option.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(blocker == nil ? Color.secondary : Color.orange)
                                }
                                Spacer()
                                if quality == option && blocker == nil {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.yellow)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .disabled(blocker != nil || exporter.isBusy)
                    }
                } header: {
                    Text("Qualität")
                } footer: {
                    Text("Alle Optionen exportieren in der vollen Original-Auflösung. „Verlustfrei“ kopiert die Originaldaten 1:1 und geht nur, wenn du nur geschnitten/getrimmt hast.")
                }

                Section { actionSection }
            }
            .navigationTitle("Exportieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") { dismiss() }.disabled(exporter.isBusy)
                }
            }
        }
        .interactiveDismissDisabled(exporter.isBusy)
        .onAppear {
            quality = model.state.losslessBlocker == nil ? .lossless : .hevc
            model.player.pause()
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        switch exporter.phase {
        case .idle:
            Button {
                Task { await exporter.export(state: model.state, quality: quality) }
            } label: {
                Label("Exportieren & in Fotos sichern", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .font(.headline)
            }
        case .exporting:
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: Double(exporter.progress))
                HStack {
                    Text("Exportiere … \(Int(exporter.progress * 100)) %").monospacedDigit()
                    Spacer()
                    Button("Abbrechen", role: .destructive) { exporter.cancel() }
                }
                Text("App bitte geöffnet lassen.").font(.caption).foregroundStyle(.secondary)
            }
        case .saving:
            HStack {
                ProgressView()
                Text("Speichere in Fotos …")
            }
        case .done(let url, let saved, let note):
            VStack(alignment: .leading, spacing: 10) {
                Label(saved ? "In der Fotos-App gespeichert" : "Export fertig",
                      systemImage: saved ? "checkmark.seal.fill" : "checkmark")
                    .foregroundStyle(.green)
                    .font(.headline)
                if let note { Text(note).font(.caption).foregroundStyle(.orange) }
                ShareLink(item: url) {
                    Label("Teilen / In Dateien sichern", systemImage: "square.and.arrow.up")
                }
                Button("Noch einmal exportieren") { exporter.reset() }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message).foregroundStyle(.red)
                Button("Erneut versuchen") { exporter.reset() }
            }
        }
    }

    private func blocker(for option: ExportQuality) -> String? {
        switch option {
        case .lossless: return model.state.losslessBlocker
        case .prores: return ExportQuality.isProResAvailable ? nil : "Auf diesem iPhone nicht verfügbar."
        case .hevc, .h264: return nil
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
