import SwiftUI

struct EditToolbar: View {
    @EnvironmentObject private var model: EditorModel
    @Binding var sheet: EditorSheet?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                if model.selectedClip != nil {
                    ToolButton(title: "Schneiden", icon: "scissors") { model.splitAtPlayhead() }
                    ToolButton(title: "Trimmen", icon: "timeline.selection") { sheet = .trim }
                    ToolButton(title: "Tempo", icon: "speedometer") { sheet = .speed }
                    ToolButton(title: "Ton", icon: "speaker.wave.2") { sheet = .volume }
                    ToolButton(title: "Filter", icon: "camera.filters") { sheet = .filter }
                    ToolButton(title: "Anpassen", icon: "slider.horizontal.3") { sheet = .adjust }
                    ToolButton(title: "Kopieren", icon: "plus.square.on.square") { model.duplicateSelected() }
                    ToolButton(title: "Nach vorn", icon: "arrow.left") { model.moveSelected(by: -1) }
                    ToolButton(title: "Nach hinten", icon: "arrow.right") { model.moveSelected(by: 1) }
                    ToolButton(title: "Löschen", icon: "trash", destructive: true) { model.deleteSelected() }
                    Divider().frame(height: 36).overlay(Color.white.opacity(0.2))
                }
                ToolButton(title: "Text", icon: "textformat") { sheet = .text }
                ToolButton(title: "Musik", icon: "music.note") { sheet = .music }
                ToolButton(title: "Format", icon: "aspectratio") { sheet = .canvas }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 6)
        .background(Color(white: 0.05))
    }
}

struct ToolButton: View {
    let title: String
    let icon: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 20))
                Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .frame(width: 66, height: 54)
            .foregroundStyle(destructive ? Color.red : Color.white)
        }
    }
}
