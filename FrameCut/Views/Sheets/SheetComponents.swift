import SwiftUI

struct SheetHost: View {
    let sheet: EditorSheet

    var body: some View {
        switch sheet {
        case .trim: TrimSheet()
        case .speed: SpeedSheet()
        case .volume: VolumeSheet()
        case .filter: FilterSheet()
        case .adjust: AdjustSheet()
        case .text: TextSheet()
        case .music: MusicSheet()
        case .canvas: CanvasSheet()
        case .export: ExportSheet()
        }
    }
}

struct SheetContainer<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Fertig") { dismiss() }.fontWeight(.semibold)
            }
            .padding()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { String(format: "%.2f", $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.subheadline)
            Slider(value: $value, in: range)
        }
    }
}

struct NoClipSelectedHint: View {
    var body: some View {
        Text("Tippe zuerst in der Timeline auf einen Clip.")
            .foregroundStyle(.secondary)
    }
}

func percentString(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }
