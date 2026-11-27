import SwiftUI
import AVFoundation
import Combine
import PhotosUI

@MainActor
final class EditorModel: ObservableObject {
    @Published var state = EditorState()
    @Published var selectedClipID: UUID?
    @Published var selectedTextID: UUID?
    @Published var currentTime: Double = 0
    @Published private(set) var isPlaying = false
    @Published var busyMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    let player = AVPlayer()
    private(set) var isScrubbing = false

    private var cancellables = Set<AnyCancellable>()
    private var rebuildTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var history: [EditorState] = []
    private var future: [EditorState] = []
    private var committed = EditorState()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        player.actionAtItemEnd = .pause

        // Rebuild the preview shortly after every edit.
        $state
            .removeDuplicates()
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] newState in self?.rebuild(newState) }
            .store(in: &cancellables)

        // Undo history (slider drags are grouped into one step).
        $state
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] newState in self?.commit(newState) }
            .store(in: &cancellables)

        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.isPlaying = status != .paused }
            .store(in: &cancellables)

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing, time.isNumeric else { return }
                self.currentTime = min(time.seconds, self.state.totalDuration)
            }
        }
    }

    // MARK: - Playback

    func togglePlay() {
        guard player.currentItem != nil else { return }
        if isPlaying {
            player.pause()
        } else {
            if currentTime >= state.totalDuration - 0.05 { seek(to: 0) }
            player.play()
        }
    }

    func seek(to seconds: Double) {
        let clamped = min(max(0, seconds), state.totalDuration)
        currentTime = clamped
        player.seek(to: CompositionBuilder.cmTime(clamped), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func beginScrub() {
        isScrubbing = true
        if isPlaying { player.pause() }
    }

    func scrub(to seconds: Double) { seek(to: seconds) }

    func endScrub() { isScrubbing = false }

    private func rebuild(_ newState: EditorState) {
        rebuildTask?.cancel()
        guard !newState.clips.isEmpty else {
            player.replaceCurrentItem(with: nil)
            currentTime = 0
            return
        }
        let resumeAt = min(currentTime, newState.totalDuration)
        let resumePlaying = isPlaying

        rebuildTask = Task { [weak self] in
            do {
                let built = try await CompositionBuilder.build(state: newState, passthrough: false)
                guard let self, !Task.isCancelled else { return }
                let item = AVPlayerItem(asset: built.asset)
                item.videoComposition = built.videoComposition
                item.audioMix = built.audioMix
                item.audioTimePitchAlgorithm = .spectral
                self.player.replaceCurrentItem(with: item)
                _ = await self.player.seek(to: CompositionBuilder.cmTime(resumeAt), toleranceBefore: .zero, toleranceAfter: .zero)
                if resumePlaying { self.player.play() }
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Undo / Redo

    private func commit(_ newState: EditorState) {
        guard newState != committed else { return }
        history.append(committed)
        if history.count > 60 { history.removeFirst() }
        future.removeAll()
        committed = newState
        updateUndoFlags()
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        future.append(committed)
        committed = previous
        state = previous
        updateUndoFlags()
    }

    func redo() {
        guard let next = future.popLast() else { return }
        history.append(committed)
        committed = next
        state = next
        updateUndoFlags()
    }

    private func updateUndoFlags() {
        canUndo = !history.isEmpty
        canRedo = !future.isEmpty
    }

    // MARK: - Import

    func importPickerItems(_ items: [PhotosPickerItem]) async {
        busyMessage = "Importiere \(items.count) Video(s) in Originalqualität …"
        defer { busyMessage = nil }
        for item in items {
            do {
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { continue }
                addClip(try await Clip.load(url: movie.url))
            } catch {
                errorMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func importFiles(_ urls: [URL]) async {
        busyMessage = "Importiere Datei(en) …"
        defer { busyMessage = nil }
        for url in urls {
            do {
                let copy = try MediaStore.copyIntoLibrary(url)
                addClip(try await Clip.load(url: copy))
            } catch {
                errorMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    private func addClip(_ clip: Clip) {
        state.clips.append(clip)
        if selectedClipID == nil { selectedClipID = clip.id }
    }

    func setMusic(from url: URL) async {
        busyMessage = "Lade Musik …"
        defer { busyMessage = nil }
        do {
            let copy = try MediaStore.copyIntoLibrary(url)
            let asset = AVURLAsset(url: copy)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard !audioTracks.isEmpty else {
                errorMessage = "Die Datei enthält keine Tonspur (oder ist kopiergeschützt)."
                return
            }
            let duration = try await asset.load(.duration).seconds
            state.music = MusicTrack(url: copy, name: url.deletingPathExtension().lastPathComponent, duration: duration)
        } catch {
            errorMessage = "Musik konnte nicht geladen werden: \(error.localizedDescription)"
        }
    }

    func newProject() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = EditorState()
        committed = state
        history.removeAll()
        future.removeAll()
        updateUndoFlags()
        selectedClipID = nil
        selectedTextID = nil
        currentTime = 0
        MediaStore.deleteEverything()
    }

    // MARK: - Clip editing

    var selectedClipIndex: Int? { state.clips.firstIndex { $0.id == selectedClipID } }

    var selectedClip: Clip? { selectedClipIndex.map { state.clips[$0] } }

    func updateSelectedClip(_ change: (inout Clip) -> Void) {
        guard let index = selectedClipIndex else { return }
        change(&state.clips[index])
    }

    func selectClip(_ id: UUID, atOffset offset: Double) {
        selectedClipID = id
        if let start = state.startTime(ofClip: id) { seek(to: start + offset) }
    }

    func seekToSelectedClip(end: Bool = false) {
        guard let clip = selectedClip, let start = state.startTime(ofClip: clip.id) else { return }
        seek(to: end ? start + clip.duration - 0.04 : start)
    }

    func splitAtPlayhead() {
        guard let location = state.clipLocation(at: currentTime) else { return }
        let clip = state.clips[location.index]
        let splitPoint = clip.start + location.offset * clip.speed
        guard splitPoint - clip.start > 0.05, clip.end - splitPoint > 0.05 else { return }
        var first = clip
        first.end = splitPoint
        var second = clip
        second.id = UUID()
        second.start = splitPoint
        state.clips.replaceSubrange(location.index...location.index, with: [first, second])
        selectedClipID = second.id
    }

    func deleteSelected() {
        guard let index = selectedClipIndex else { return }
        state.clips.remove(at: index)
        selectedClipID = state.clips.isEmpty ? nil : state.clips[min(index, state.clips.count - 1)].id
    }

    func duplicateSelected() {
        guard let index = selectedClipIndex else { return }
        var copy = state.clips[index]
        copy.id = UUID()
        state.clips.insert(copy, at: index + 1)
        selectedClipID = copy.id
    }

    func moveSelected(by delta: Int) {
        guard let index = selectedClipIndex else { return }
        let target = index + delta
        guard state.clips.indices.contains(target) else { return }
        state.clips.swapAt(index, target)
    }

    func applyLookToAll() {
        guard let clip = selectedClip else { return }
        for i in state.clips.indices {
            state.clips[i].filter = clip.filter
            state.clips[i].adjust = clip.adjust
        }
    }

    func applyVolumeToAll() {
        guard let clip = selectedClip else { return }
        for i in state.clips.indices {
            state.clips[i].volume = clip.volume
            state.clips[i].isMuted = clip.isMuted
        }
    }

    // MARK: - Text editing

    var selectedText: TextOverlay? { state.texts.first { $0.id == selectedTextID } }

    func updateSelectedText(_ change: (inout TextOverlay) -> Void) {
        guard let index = state.texts.firstIndex(where: { $0.id == selectedTextID }) else { return }
        change(&state.texts[index])
    }

    func addText() {
        let total = state.totalDuration
        let start = min(currentTime, max(0, total - 1))
        let overlay = TextOverlay(start: start, duration: min(3, max(0.5, total - start)))
        state.texts.append(overlay)
        selectedTextID = overlay.id
    }

    func deleteSelectedText() {
        state.texts.removeAll { $0.id == selectedTextID }
        selectedTextID = state.texts.last?.id
    }
}
