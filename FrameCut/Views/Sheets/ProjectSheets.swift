import SwiftUI

// MARK: - Text

struct TextSheet: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        SheetContainer(title: "Text") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button { model.addText() } label: { Label("Neu", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(.black)
                    ForEach(model.state.texts) { overlay in
                        Button(overlay.text.isEmpty ? "–" : String(overlay.text.prefix(14))) {
                            model.selectedTextID = overlay.id
                            model.seek(to: overlay.start)
                        }
                        .buttonStyle(.bordered)
                        .tint(overlay.id == model.selectedTextID ? .yellow : .gray)
                    }
                }
            }

            if let overlay = model.selectedText {
                TextField("Text", text: binding(\.text), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                ColorPicker("Farbe", selection: binding(\.color), supportsOpacity: false)
                Toggle("Fett", isOn: binding(\.bold))
                Toggle("Hintergrund-Box", isOn: binding(\.background))
                LabeledSlider(title: "Größe", value: binding(\.size), range: 0.03...0.15, format: percentString)

                HStack {
                    Text("Position").font(.subheadline)
                    Spacer()
                    positionButton("Oben", y: 0.15)
                    positionButton("Mitte", y: 0.5)
                    positionButton("Unten", y: 0.82)
                }
                LabeledSlider(title: "Horizontal", value: binding(\.x), range: 0...1, format: percentString)
                LabeledSlider(title: "Vertikal", value: binding(\.y), range: 0...1, format: percentString)

                let total = max(0.5, model.state.totalDuration)
                LabeledSlider(title: "Start", value: binding(\.start), range: 0...total, format: { $0.timecode })
                LabeledSlider(title: "Dauer", value: binding(\.duration), range: 0.2...max(0.3, total), format: { $0.timecode })
                Text("Sichtbar von \(overlay.start.timecode) bis \(overlay.end.timecode)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Start = Playhead") {
                        let now = model.currentTime
                        model.updateSelectedText { $0.start = now }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Löschen", role: .destructive) { model.deleteSelectedText() }
                        .buttonStyle(.bordered)
                }
            } else if model.state.texts.isEmpty {
                Text("Füge einen Text hinzu. Er wird beim Export in voller Auflösung scharf ins Bild gerendert.")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if model.selectedTextID == nil { model.selectedTextID = model.state.texts.first?.id }
        }
    }

    private func positionButton(_ title: String, y: Double) -> some View {
        Button(title) {
            model.updateSelectedText {
                $0.y = y
                $0.x = 0.5
            }
        }
        .buttonStyle(.bordered)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<TextOverlay, T>) -> Binding<T> {
        Binding(
            get: { (model.selectedText ?? TextOverlay(start: 0))[keyPath: keyPath] },
            set: { value in model.updateSelectedText { $0[keyPath: keyPath] = value } }
        )
    }
}

// MARK: - Music

struct MusicSheet: View {
    @EnvironmentObject private var model: EditorModel
    @State private var showImporter = false

    var body: some View {
        SheetContainer(title: "Musik") {
            if let music = model.state.music {
                Label(music.name, systemImage: "music.note").font(.headline)
                LabeledSlider(
                    title: "Musik-Lautstärke",
                    value: Binding(
                        get: { Double(model.state.music?.volume ?? 0.8) },
                        set: { value in model.state.music?.volume = Float(value) }
                    ),
                    range: 0...1,
                    format: percentString
                )
                LabeledSlider(
                    title: "Startpunkt im Song",
                    value: Binding(
                        get: { model.state.music?.offset ?? 0 },
                        set: { value in model.state.music?.offset = value }
                    ),
                    range: 0...max(0.1, music.duration - 1),
                    format: { $0.timecode }
                )
                Toggle("Wiederholen, wenn der Song kürzer ist", isOn: Binding(
                    get: { model.state.music?.loop ?? true },
                    set: { value in model.state.music?.loop = value }
                ))
                Toggle("Am Ende ausblenden", isOn: Binding(
                    get: { model.state.music?.fadeOut ?? true },
                    set: { value in model.state.music?.fadeOut = value }
                ))
                HStack {
                    Button("Anderer Song") { showImporter = true }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Entfernen", role: .destructive) { model.state.music = nil }
                        .buttonStyle(.bordered)
                }
            } else {
                Button { showImporter = true } label: {
                    Label("Song aus Dateien wählen", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
                Text("MP3, M4A, WAV, AIFF … Songs aus Apple Music sind kopiergeschützt und lassen sich nicht verwenden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !model.state.clips.isEmpty {
                Divider()
                LabeledSlider(
                    title: "Original-Ton aller Clips",
                    value: Binding(
                        get: { Double(model.state.clips.first?.volume ?? 1) },
                        set: { value in
                            for i in model.state.clips.indices { model.state.clips[i].volume = Float(value) }
                        }
                    ),
                    range: 0...1,
                    format: percentString
                )
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result {
                Task { await model.setMusic(from: url) }
            }
        }
    }
}

// MARK: - Canvas

struct CanvasSheet: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        SheetContainer(title: "Format") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                ForEach(CanvasAspect.allCases) { aspect in
                    let selected = model.state.canvas == aspect
                    Button { model.state.canvas = aspect } label: {
                        VStack(spacing: 6) {
                            shape(for: aspect)
                                .stroke(selected ? Color.yellow : Color.white.opacity(0.6), lineWidth: 2)
                                .frame(width: 60, height: 60)
                            Text(aspect.title).font(.subheadline.bold())
                            Text(aspect.subtitle).font(.caption2).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(Color.white.opacity(selected ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.white)
                }
            }
            Text("Ausgabe: \(model.state.renderSize.resolutionLabel). Die Auflösung richtet sich nach deinem ersten Clip, es wird nichts verkleinert.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func shape(for aspect: CanvasAspect) -> some Shape {
        let ratio = aspect.ratio ?? (model.state.clips.first.map { $0.orientedSize.width / max(1, $0.orientedSize.height) } ?? 1)
        let w: CGFloat = ratio >= 1 ? 56 : 56 * ratio
        let h: CGFloat = ratio >= 1 ? 56 / ratio : 56
        return RoundedRectangle(cornerRadius: 4).path(in: CGRect(x: (60 - w) / 2, y: (60 - h) / 2, width: w, height: h))
    }
}
