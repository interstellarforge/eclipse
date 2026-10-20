import AppKit
import SwiftUI

/// The look of the app: charcoal panels, one purple accent, rounded corners.
enum Theme {
    static let background = Color(red: 0.031, green: 0.039, blue: 0.094)       // window
    static let panel = Color(red: 0.051, green: 0.063, blue: 0.141)            // side panels
    static let raised = Color(red: 0.078, green: 0.098, blue: 0.204)           // cards, fields
    static let hover = Color(red: 0.114, green: 0.137, blue: 0.278)
    static let stroke = Color.white.opacity(0.07)
    static let text = Color(red: 0.93, green: 0.93, blue: 0.95)
    static let dim = Color(red: 0.62, green: 0.63, blue: 0.69)
    static let accent = Color(red: 0.482, green: 0.239, blue: 1.0)
    static let accentSoft = Color(red: 0.482, green: 0.239, blue: 1.0).opacity(0.18)
    static let video = Color(red: 0.31, green: 0.38, blue: 0.85)
    static let audio = Color(red: 0.16, green: 0.62, blue: 0.45)
    static let music = Color(red: 0.55, green: 0.30, blue: 0.85)
    static let titleClip = Color(red: 0.50, green: 0.22, blue: 0.70)
    static let overlayClip = Color(red: 0.12, green: 0.55, blue: 0.62)
    static let radius: CGFloat = 12
    static let smallRadius: CGFloat = 8
}

extension View {
    /// A rounded raised card.
    func card(_ fill: Color = Theme.raised, radius: CGFloat = Theme.radius) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius)).overlay(RoundedRectangle(cornerRadius: radius).stroke(Theme.stroke))
    }

    func panelBackground() -> some View { background(Theme.panel) }
}

/// SwiftUI's @State is not usable with this toolchain, so small bits of view state live in tiny observable objects.
final class Flag: ObservableObject { @Published var on = false }
final class Memory<T>: ObservableObject { var value: T? }

/// Round icon button used in the bars.
struct IconButton: View {
    let symbol: String
    var help: String
    var active = false
    var size: CGFloat = 15
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? Theme.accent : Theme.text)
                .frame(width: 30, height: 28)
                .background(active ? Theme.accentSoft : (hover.on ? Theme.hover : .clear), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).help(help)
        .onHover { hover.on = $0 }
    }
}

/// A thin drag handle between panels. Drags change `value` (the size of the panel on one side).
struct PanelHandle: View {
    enum Edge { case rightOfLeft, leftOfRight, aboveBottom }
    let edge: Edge
    @Binding var value: Double
    let range: ClosedRange<Double>
    @StateObject private var start = Memory<Double>()

    var body: some View {
        let vertical = edge != .aboveBottom
        Rectangle().fill(Color.clear)
            .frame(width: vertical ? 7 : nil, height: vertical ? nil : 7)
            .overlay(Rectangle().fill(Theme.stroke).frame(width: vertical ? 1 : nil, height: vertical ? nil : 1))
            .contentShape(Rectangle())
            .onHover { inside in if inside { (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { g in
                if start.value == nil { start.value = value }
                let delta: Double
                switch edge {
                case .rightOfLeft: delta = g.translation.width
                case .leftOfRight: delta = -g.translation.width
                case .aboveBottom: delta = -g.translation.height
                }
                value = min(max((start.value ?? value) + delta, range.lowerBound), range.upperBound)
            }.onEnded { _ in start.value = nil })
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim).textCase(.uppercase).tracking(0.6) }
}

struct Chip: View {
    let title: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize().padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(selected ? .white : Theme.dim)
                .background(selected ? Theme.accent : Theme.raised, in: Capsule())
        }.buttonStyle(.plain)
    }
}
