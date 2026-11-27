import SwiftUI

/// CapCut-style timeline: the playhead stays in the middle, the content moves.
/// Drag = scrub, pinch = zoom, tap a clip = select.
struct TimelineView: View {
    @EnvironmentObject private var model: EditorModel
    var onAddClip: () -> Void
    var onOpenText: () -> Void
    var onOpenMusic: () -> Void

    @State private var pointsPerSecond: CGFloat = 50
    @State private var dragStartTime: Double?
    @State private var zoomStart: CGFloat?

    private var pps: CGFloat { pointsPerSecond }

    var body: some View {
        GeometryReader { geo in
            let center = geo.size.width / 2
            let originX = center - CGFloat(model.currentTime) * pps

            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    TimeRuler(duration: model.state.totalDuration, pps: pps)
                    clipRow.frame(height: 64)
                    textRow.frame(height: 24)
                    musicRow.frame(height: 24)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, 8)
                .offset(x: originX)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: geo.size.height)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .offset(x: center - 1)
                    .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if dragStartTime == nil {
                            dragStartTime = model.currentTime
                            model.beginScrub()
                        }
                        let start = dragStartTime ?? 0
                        model.scrub(to: start - Double(value.translation.width / pps))
                    }
                    .onEnded { _ in
                        dragStartTime = nil
                        model.endScrub()
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if zoomStart == nil { zoomStart = pointsPerSecond }
                        pointsPerSecond = min(400, max(6, (zoomStart ?? 50) * value.magnification))
                    }
                    .onEnded { _ in zoomStart = nil }
            )
        }
        .background(Color(white: 0.08))
    }

    private var clipRow: some View {
        HStack(spacing: 0) {
            ForEach(model.state.clips) { clip in
                ClipTile(
                    clip: clip,
                    width: max(6, CGFloat(clip.duration) * pps),
                    selected: clip.id == model.selectedClipID
                )
                .onTapGesture(count: 1, coordinateSpace: .local) { location in
                    model.selectClip(clip.id, atOffset: Double(location.x / pps))
                }
            }
            Button(action: onAddClip) {
                Image(systemName: "plus")
                    .font(.title3.bold())
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.leading, 10)
        }
    }

    private var textRow: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: max(1, CGFloat(model.state.totalDuration) * pps), height: 24)
            if model.state.texts.isEmpty {
                Button(action: onOpenText) {
                    Label("Text hinzufügen", systemImage: "textformat")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                .foregroundStyle(.white)
            }
            ForEach(model.state.texts) { overlay in
                Text(overlay.text)
                    .font(.caption2.bold())
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(width: max(8, CGFloat(overlay.duration) * pps), height: 24, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(overlay.id == model.selectedTextID ? Color.orange : Color.purple.opacity(0.8))
                    )
                    .clipped()
                    .offset(x: CGFloat(overlay.start) * pps)
                    .onTapGesture {
                        model.selectedTextID = overlay.id
                        onOpenText()
                    }
            }
        }
    }

    private var musicRow: some View {
        ZStack(alignment: .topLeading) {
            if let music = model.state.music {
                Label(music.name, systemImage: "music.note")
                    .font(.caption2.bold())
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(width: max(30, CGFloat(model.state.totalDuration) * pps), height: 24, alignment: .leading)
                    .background(Color.green.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                    .onTapGesture(perform: onOpenMusic)
            } else {
                Button(action: onOpenMusic) {
                    Label("Musik hinzufügen", systemImage: "music.note")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                .foregroundStyle(.white)
            }
        }
    }
}

struct ClipTile: View {
    let clip: Clip
    let width: CGFloat
    let selected: Bool

    var body: some View {
        let inner = max(4, width - 2)
        let count = min(30, max(1, Int(inner / 56)))
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                ClipThumbnail(
                    url: clip.url,
                    time: clip.start + (Double(i) + 0.5) / Double(count) * clip.sourceDuration
                )
                .frame(width: inner / CGFloat(count), height: 64)
                .clipped()
            }
        }
        .frame(width: inner, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .bottomLeading) {
            if inner > 50 {
                HStack(spacing: 4) {
                    if abs(clip.speed - 1) > 0.001 {
                        Text(String(format: "%.2g×", clip.speed))
                    }
                    if clip.isMuted { Image(systemName: "speaker.slash.fill") }
                    if clip.hasLookChanges { Image(systemName: "camera.filters") }
                    Text(clip.duration.shortTime)
                }
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                .padding(3)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Color.yellow : Color.white.opacity(0.15), lineWidth: selected ? 3 : 1)
        )
        .padding(.horizontal, 1)
    }
}

struct ClipThumbnail: View {
    let url: URL
    let time: Double
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(white: 0.2)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .task(id: "\(url.lastPathComponent)-\(Int(time * 2))") {
            image = await Thumbnails.image(url: url, time: time)
        }
    }
}

struct TimeRuler: View {
    let duration: Double
    let pps: CGFloat

    var body: some View {
        let step: Double = pps >= 120 ? 1 : pps >= 50 ? 2 : pps >= 20 ? 5 : pps >= 8 ? 10 : 30
        Canvas { context, size in
            var t = 0.0
            while t <= duration + 0.001 {
                let x = CGFloat(t) * pps
                context.fill(Path(CGRect(x: x, y: size.height - 4, width: 1, height: 4)), with: .color(.white.opacity(0.4)))
                context.draw(
                    Text(t.shortTime).font(.system(size: 9)).foregroundColor(.white.opacity(0.5)),
                    at: CGPoint(x: x + 2, y: 5),
                    anchor: .leading
                )
                t += step
            }
        }
        .frame(width: max(1, CGFloat(duration) * pps + 30), height: 14)
    }
}
