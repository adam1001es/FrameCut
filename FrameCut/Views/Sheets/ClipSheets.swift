import SwiftUI

// MARK: - Trim

struct TrimSheet: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        SheetContainer(title: "Trimmen") {
            if let clip = model.selectedClip, clip.assetDuration > 0.2 {
                LabeledSlider(
                    title: "Anfang",
                    value: Binding(
                        get: { model.selectedClip?.start ?? 0 },
                        set: { value in
                            model.updateSelectedClip { $0.start = min(max(0, value), $0.end - 0.1) }
                            model.seekToSelectedClip()
                        }
                    ),
                    range: 0...clip.assetDuration,
                    format: { $0.timecode }
                )
                LabeledSlider(
                    title: "Ende",
                    value: Binding(
                        get: { model.selectedClip?.end ?? 0 },
                        set: { value in
                            model.updateSelectedClip { $0.end = max(min(clip.assetDuration, value), $0.start + 0.1) }
                            model.seekToSelectedClip(end: true)
                        }
                    ),
                    range: 0...clip.assetDuration,
                    format: { $0.timecode }
                )
                Text("Verwendet: \(clip.sourceDuration.timecode) von \(clip.assetDuration.timecode)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Label("Für einen Schnitt mitten im Clip: Playhead hinziehen und auf „Schneiden“ tippen.", systemImage: "scissors")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                NoClipSelectedHint()
            }
        }
    }
}

// MARK: - Speed

struct SpeedSheet: View {
    @EnvironmentObject private var model: EditorModel
    private let presets: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4]

    var body: some View {
        SheetContainer(title: "Tempo") {
            if let clip = model.selectedClip {
                LabeledSlider(
                    title: "Geschwindigkeit",
                    value: Binding(
                        get: { log2(model.selectedClip?.speed ?? 1) },
                        set: { value in model.updateSelectedClip { $0.speed = (pow(2, value) * 100).rounded() / 100 } }
                    ),
                    range: -2...2,
                    format: { String(format: "%.2f×", pow(2, $0)) }
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(presets, id: \.self) { speed in
                            Button(String(format: "%g×", speed)) {
                                model.updateSelectedClip { $0.speed = speed }
                            }
                            .buttonStyle(.bordered)
                            .tint(abs(clip.speed - speed) < 0.001 ? .yellow : .gray)
                        }
                    }
                }
                Text("Neue Länge: \(clip.duration.timecode). Die Tonhöhe wird automatisch korrigiert.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Tipp: Für flüssige Zeitlupe mit 60 oder 120/240 fps (Slo-Mo) filmen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                NoClipSelectedHint()
            }
        }
    }
}

// MARK: - Volume

struct VolumeSheet: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        SheetContainer(title: "Ton") {
            if let clip = model.selectedClip {
                if !clip.hasAudio {
                    Text("Dieser Clip hat keine Tonspur.").foregroundStyle(.secondary)
                }
                Toggle("Stumm", isOn: Binding(
                    get: { model.selectedClip?.isMuted ?? false },
                    set: { value in model.updateSelectedClip { $0.isMuted = value } }
                ))
                LabeledSlider(
                    title: "Lautstärke",
                    value: Binding(
                        get: { Double(model.selectedClip?.volume ?? 1) },
                        set: { value in model.updateSelectedClip { $0.volume = Float(value) } }
                    ),
                    range: 0...1,
                    format: percentString
                )
                .disabled(clip.isMuted)
                Button("Auf alle Clips anwenden") { model.applyVolumeToAll() }
                    .buttonStyle(.bordered)
            } else {
                NoClipSelectedHint()
            }
        }
    }
}

// MARK: - Filter

struct FilterSheet: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        SheetContainer(title: "Filter") {
            if let clip = model.selectedClip {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 12) {
                    ForEach(FilterPreset.allCases) { filter in
                        FilterPreviewTile(clip: clip, filter: filter, selected: clip.filter == filter)
                            .onTapGesture { model.updateSelectedClip { $0.filter = filter } }
                    }
                }
                Button("Auf alle Clips anwenden") { model.applyLookToAll() }
                    .buttonStyle(.bordered)
            } else {
                NoClipSelectedHint()
            }
        }
    }
}

struct FilterPreviewTile: View {
    let clip: Clip
    let filter: FilterPreset
    let selected: Bool
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Color(white: 0.2)
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.yellow : .clear, lineWidth: 3))
            Text(filter.title)
                .font(.caption2)
                .foregroundStyle(selected ? .yellow : .primary)
        }
        .task(id: "\(filter.id)-\(clip.url.lastPathComponent)-\(clip.start)") {
            image = await FrameLook.preview(clip: clip, filter: filter)
        }
    }
}

// MARK: - Adjust

struct AdjustSheet: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        SheetContainer(title: "Anpassen") {
            if model.selectedClip != nil {
                LabeledSlider(title: "Belichtung", value: binding(\.exposure), range: -2...2, format: { String(format: "%+.1f EV", $0) })
                LabeledSlider(title: "Helligkeit", value: binding(\.brightness), range: -0.3...0.3, format: { String(format: "%+.0f", $0 * 333) })
                LabeledSlider(title: "Kontrast", value: binding(\.contrast), range: 0.5...1.5, format: percentString)
                LabeledSlider(title: "Sättigung", value: binding(\.saturation), range: 0...2, format: percentString)
                LabeledSlider(title: "Wärme", value: binding(\.warmth), range: -1...1, format: { String(format: "%+.0f", $0 * 100) })
                LabeledSlider(title: "Schärfe", value: binding(\.sharpness), range: 0...1, format: percentString)
                LabeledSlider(title: "Vignette", value: binding(\.vignette), range: 0...1.5, format: percentString)
                HStack {
                    Button("Zurücksetzen") { model.updateSelectedClip { $0.adjust = Adjustments() } }
                        .buttonStyle(.bordered)
                    Button("Auf alle Clips anwenden") { model.applyLookToAll() }
                        .buttonStyle(.bordered)
                }
            } else {
                NoClipSelectedHint()
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<Adjustments, Double>) -> Binding<Double> {
        Binding(
            get: { model.selectedClip?.adjust[keyPath: keyPath] ?? Adjustments()[keyPath: keyPath] },
            set: { value in model.updateSelectedClip { $0.adjust[keyPath: keyPath] = value } }
        )
    }
}
