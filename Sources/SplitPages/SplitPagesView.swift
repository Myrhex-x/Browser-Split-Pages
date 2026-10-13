//
//  SplitPagesView.swift
//  SplitPages
//
//  Two pages on the same surface, with a hinge between them, opened and folded back the way a
//  foldable phone's screen does: a seam of light grows down the middle, the page goes out of focus
//  as it makes room, and the new side comes into focus. Drag the hinge to share the room (it settles
//  on thirds and halves, with a tap of the trackpad), double-click it to share it evenly, or drag it
//  nearly to an edge and let go to fold that page away.
//
//  The blur is the real page's, live, web views included: they lay themselves out again behind it as
//  they resize, which is why a foldable blurs its screen while it opens.
//

import AppKit
import SwiftUI

public struct SplitPagesView<Leading: View, Trailing: View>: View {
    @Bindable private var state: SplitPagesState
    private let gap: CGFloat
    private let releaseLabel: LocalizedStringKey
    private let leading: Leading
    private let trailing: Trailing

    /// - Parameters:
    ///   - gap: the band between the pages, where the hinge is held. The pages take every click over
    ///     themselves (web views do), so it needs a few points.
    ///   - releaseLabel: what a page about to be folded away says.
    public init(state: SplitPagesState, gap: CGFloat = 8, releaseLabel: LocalizedStringKey = "Release to close",
                @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.state = state
        self.gap = gap
        self.releaseLabel = releaseLabel
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        GeometryReader { proxy in
            // Still between openings and folds; a frame for every display refresh while one runs.
            TimelineView(.animation(minimumInterval: nil, paused: state.transition == nil)) { timeline in
                let layout = state.layout(width: proxy.size.width, gap: gap, at: timeline.date)
                HStack(spacing: layout.isSplit ? layout.gap : 0) {
                    pane(leading, side: .leading, layout: layout)
                    pane(trailing, side: .trailing, layout: layout)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                .overlay(alignment: .topLeading) {
                    if let seam = layout.seam {
                        SeamLight(glow: seam.glow, height: seam.height)
                            .frame(width: 64, height: proxy.size.height)
                            .offset(x: seam.x - 32)
                    } else if layout.showsHinge {
                        SplitHinge(state: state, usable: layout.usable)
                            .frame(width: max(gap, 6), height: proxy.size.height)
                            .offset(x: layout.hingeX - max(gap, 6) / 2)
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    /// One page: always in the view (so a web view keeps its page), zero wide when it isn't shown.
    private func pane<Content: View>(_ content: Content, side: SplitSide, layout: SplitLayout) -> some View {
        let look = layout.look(side)
        let shown = layout.width(side) > 0
        let folding = state.foldPreview?.side == side ? max(0.08, state.foldPreview?.depth ?? 0) : 0
        return content
            .blur(radius: look.blur)
            .opacity(look.opacity)
            .overlay {
                if layout.isSplit, state.focused != side, folding == 0, state.transition == nil {
                    Color.black.opacity(0.05).allowsHitTesting(false)
                }
            }
            .overlay {
                if folding > 0 {
                    ZStack {
                        Color.black.opacity(0.12 + 0.28 * folding)
                        VStack(spacing: 8) {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .medium))
                            Text(releaseLabel)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .opacity(min(1, folding * 2))
                    }
                    .allowsHitTesting(false)
                }
            }
            .simultaneousGesture(TapGesture().onEnded { if layout.isSplit { state.focused = side } })
            .frame(width: layout.width(side))
            .clipped()
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
    }
}

// MARK: - The seam of light

/// The fold's light: a thin line, brightest at its middle, with spectrum light spilling either side
/// of it. It grows from the middle as a split opens, and shrinks back into it as one folds.
public struct SeamLight: View {
    /// 0 to 1.
    public var glow: Double
    /// The share of the height it covers, from the middle.
    public var height: Double
    @Environment(\.colorScheme) private var scheme

    /// Indigo to yellow, top to bottom.
    public static let spectrum: [Color] = [
        Color(red: 0.388, green: 0.400, blue: 0.945), Color(red: 0.659, green: 0.333, blue: 0.969),
        Color(red: 0.925, green: 0.282, blue: 0.600), Color(red: 0.976, green: 0.451, blue: 0.086),
        Color(red: 0.918, green: 0.702, blue: 0.031),
    ]

    public init(glow: Double, height: Double) {
        self.glow = glow
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            let length = proxy.size.height * height
            ZStack {
                LinearGradient(colors: Self.spectrum, startPoint: .top, endPoint: .bottom)
                    .frame(width: 22, height: length)
                    .blur(radius: 10)
                    .opacity(glow * (scheme == .dark ? 0.85 : 0.6))
                    .blendMode(scheme == .dark ? .plusLighter : .normal)
                LinearGradient(stops: [
                    .init(color: core.opacity(0), location: 0),
                    .init(color: core, location: 0.5),
                    .init(color: core.opacity(0), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                    .frame(width: 1.5, height: length)
                    .opacity(glow)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var core: Color { scheme == .dark ? .white : Color(white: 0.08) }
}

// MARK: - The hinge

/// Between the two pages: a hairline and a grip.
struct SplitHinge: View {
    @Bindable var state: SplitPagesState
    /// The width the two pages share.
    let usable: CGFloat
    @State private var dragStart: Double?
    @State private var hovering = false
    @State private var snapped: Double?

    private var dragging: Bool { dragStart != nil }

    var body: some View {
        let active = hovering || dragging
        ZStack {
            Color.clear
            Rectangle()
                .fill(Color.primary.opacity(active ? 0.16 : 0.1))
                .frame(width: 1)
            if dragging {
                SeamLight(glow: state.foldPreview == nil ? 0.55 : 0.9, height: 1)
                    .frame(width: 64)
                    .transition(.opacity)
            }
            Capsule()
                .fill(Color.primary.opacity(active ? 0.7 : 0.24))
                .frame(width: active ? 5 : 4, height: dragging ? 64 : (hovering ? 48 : 32))
            if dragging {
                Text(SplitHingeMath.label(state.ratio))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(.regularMaterial))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    .fixedSize()
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 14)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            // In the window's coordinates: the hinge moves under the pointer, so its own would drift.
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStart ?? state.ratio
                    if dragStart == nil { withAnimation(.snappy) { dragStart = start } }
                    let resolved = SplitHingeMath.resolve(start + value.translation.width / max(usable, 1))
                    if resolved.snapped != snapped {
                        if resolved.snapped != nil { Self.tap(.alignment) }
                        snapped = resolved.snapped
                    }
                    state.ratio = resolved.ratio
                    let wasFolding = state.foldPreview != nil
                    state.foldPreview = resolved.folding.map { SplitPagesState.FoldPreview(side: $0, depth: resolved.depth) }
                    if !wasFolding, state.foldPreview != nil { Self.tap(.levelChange) }
                }
                .onEnded { value in
                    // Where the pointer let go (a quick drag can end past its last change).
                    let resolved = SplitHingeMath.resolve((dragStart ?? state.ratio) + value.translation.width / max(usable, 1))
                    withAnimation(.snappy) { dragStart = nil }
                    snapped = nil
                    state.foldPreview = nil
                    if let side = resolved.folding {
                        state.fold(keeping: side.other)
                    } else {
                        let settled = SplitHingeMath.settle(resolved.ratio)
                        withAnimation(.smooth) { state.ratio = settled }
                    }
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.smooth) { state.center() }
            Self.tap(.alignment)
        }
        .animation(.snappy, value: hovering)
        .accessibilityElement()
        .accessibilityLabel("Hinge between the pages")
        .accessibilityValue(SplitHingeMath.label(state.ratio))
        .accessibilityAdjustableAction { direction in
            let next = SplitHingeMath.settle(state.ratio + (direction == .increment ? 0.05 : -0.05))
            withAnimation(.smooth) { state.ratio = next }
        }
    }

    /// A tap on a Force Touch trackpad.
    static func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
