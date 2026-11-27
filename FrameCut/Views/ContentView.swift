import SwiftUI
import PhotosUI
import AVFoundation

enum EditorSheet: String, Identifiable {
    case trim, speed, volume, filter, adjust, text, music, canvas, export
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var model = EditorModel()
    @State private var sheet: EditorSheet?
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var confirmNewProject = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.state.clips.isEmpty {
                    EmptyProjectView(
                        onPhotos: { showPhotoPicker = true },
                        onFiles: { showFileImporter = true }
                    )
                } else {
                    PreviewArea()
                    TransportBar()
                    TimelineView(
                        onAddClip: { showPhotoPicker = true },
                        onOpenText: { sheet = .text },
                        onOpenMusic: { sheet = .music }
                    )
                    .frame(height: 176)
                    EditToolbar(sheet: $sheet)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .environmentObject(model)
        .preferredColorScheme(.dark)
        .tint(.yellow)
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $pickerItems,
            maxSelectionCount: nil,
            selectionBehavior: .ordered,
            matching: .videos,
            preferredItemEncoding: .current   // Original-Datei, keine Umwandlung durch iOS
        )
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await model.importPickerItems(items)
                pickerItems = []
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.movie], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await model.importFiles(urls) }
            }
        }
        .sheet(item: $sheet) { sheet in
            SheetHost(sheet: sheet)
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(.yellow)
                .presentationDetents(sheet == .export ? [.large] : [.height(360), .medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Neues Projekt starten?", isPresented: $confirmNewProject, titleVisibility: .visible) {
            Button("Projekt verwerfen", role: .destructive) { model.newProject() }
        } message: {
            Text("Alle Clips im Projekt werden entfernt. Deine Originale in der Fotos-App bleiben unberührt.")
        }
        .overlay {
            if let message = model.busyMessage {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text(message).font(.subheadline).multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(40)
                }
            }
        }
        .alert("Hinweis", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Menu {
                Button(role: .destructive) { confirmNewProject = true } label: {
                    Label("Neues Projekt", systemImage: "doc.badge.plus")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            Menu {
                Button { showPhotoPicker = true } label: { Label("Aus Fotos", systemImage: "photo.on.rectangle") }
                Button { showFileImporter = true } label: { Label("Aus Dateien", systemImage: "folder") }
            } label: {
                Image(systemName: "plus.circle.fill")
            }
        }
        ToolbarItem(placement: .principal) {
            Text("FrameCut").font(.headline)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { sheet = .export } label: {
                Label("Export", systemImage: "square.and.arrow.up").labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(.black)
            .disabled(model.state.clips.isEmpty)
        }
    }
}

// MARK: - Empty state

struct EmptyProjectView: View {
    let onPhotos: () -> Void
    let onFiles: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            Text("Neues Projekt").font(.title.bold())
            Text("Videos werden als Original-Datei importiert: volle Auflösung, HDR, 60 fps, ProRes. Nichts wird vorab komprimiert.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: onPhotos) {
                Label("Videos aus Fotos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: 260)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(.black)
            Button(action: onFiles) {
                Label("Aus Dateien", systemImage: "folder")
                    .frame(maxWidth: 260)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

struct PreviewArea: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        ZStack {
            Color.black
            PlayerView(player: model.player)
                .aspectRatio(model.state.renderSize, contentMode: .fit)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.togglePlay() }
    }
}

struct PlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

struct TransportBar: View {
    @EnvironmentObject private var model: EditorModel

    var body: some View {
        HStack(spacing: 14) {
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo)

            Spacer()

            Text("\(model.currentTime.timecode) / \(model.state.totalDuration.timecode)")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)

            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 44, height: 36)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(model.state.renderSize.resolutionLabel)
                Text("\(Int(model.state.frameRate.rounded())) fps\(model.state.isHDR ? " · HDR" : "")")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.yellow)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(white: 0.05))
    }
}
