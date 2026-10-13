//
//  SplitPagesState.swift
//  SplitPages
//
//  What a split surface knows: whether it shows one page or two, how the room is shared, which page
//  has the keyboard, and the opening or fold under way. Your app holds one, puts its two pages in a
//  SplitPagesView, and calls unfold(), fold(keeping:) or toggle() (⌘\ is a good key for it).
//

import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class SplitPagesState {
    /// An opening or a fold, drawn from `start` by the view.
    public struct Transition: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// `revealing` comes in beside the page on screen.
            case unfold(revealing: SplitSide)
            /// `closing` goes; the other page takes the surface.
            case fold(closing: SplitSide)
        }

        public let kind: Kind
        /// Where the hinge rests in the split: where it's going (opening) or where it was (folding).
        public let ratio: Double
        public let start: Date

        public var duration: Double {
            if case .unfold = kind { return FoldTimeline.unfoldDuration }
            return FoldTimeline.foldDuration
        }
    }

    /// The hinge dragged near an edge: the side that folds away if it's let go, and how close it is
    /// to the end of the hinge's travel (0 to 1).
    public struct FoldPreview: Equatable, Sendable {
        public let side: SplitSide
        public let depth: Double
    }

    /// Two pages on the surface.
    public private(set) var isSplit: Bool
    /// The leading page's share of the width while split.
    public var ratio: Double
    /// The page on the surface when there's only one.
    public private(set) var single: SplitSide
    /// The page with the keyboard. The other rests a touch dimmer.
    public var focused: SplitSide
    public private(set) var transition: Transition?
    public internal(set) var foldPreview: FoldPreview?
    /// Off: the surface changes at once (it's off by itself under Reduce Motion).
    public var animates = true
    /// After a page folds away, with the side that went.
    @ObservationIgnored public var onFold: ((SplitSide) -> Void)?

    @ObservationIgnored private var finishing: Task<Void, Never>?

    public init(split: Bool = false, ratio: Double = 0.5) {
        isSplit = split
        self.ratio = ratio
        single = .leading
        focused = .leading
    }

    /// Opens the other side beside the page on screen: a seam of light, the page going out of focus as
    /// it makes room, and the new side coming into focus.
    public func unfold() {
        guard !isSplit, transition == nil else { return }
        let revealing = single.other
        isSplit = true
        focused = revealing
        begin(.unfold(revealing: revealing))
    }

    /// Folds back to one page, `side`'s: the other goes out of focus and away.
    public func fold(keeping side: SplitSide) {
        guard isSplit, transition == nil else { return }
        foldPreview = nil
        isSplit = false
        single = side
        focused = side
        begin(.fold(closing: side.other))
    }

    /// Opens, or folds back to the page with the keyboard.
    public func toggle() {
        if isSplit { fold(keeping: focused) } else { unfold() }
    }

    /// The room shared evenly.
    public func center() {
        ratio = 0.5
    }

    private func begin(_ kind: Transition.Kind) {
        finishing?.cancel()
        let transition = Transition(kind: kind, ratio: ratio, start: Date())
        guard animates, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            self.transition = nil
            finish(transition)
            return
        }
        self.transition = transition
        finishing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(transition.duration))
            guard !Task.isCancelled, let self else { return }
            self.transition = nil
            self.finish(transition)
        }
    }

    private func finish(_ transition: Transition) {
        if case .fold(let closing) = transition.kind { onFold?(closing) }
    }

    // MARK: - The surface at a moment

    /// Where the pages are at `date`: widths, focus and the seam (used by the view, and by tests).
    public func layout(width: CGFloat, gap: CGFloat, at date: Date = Date()) -> SplitLayout {
        if let transition {
            let elapsed = date.timeIntervalSince(transition.start)
            let frame: FoldTimeline.Frame
            // The page arriving, or going: the other one stays.
            let other: SplitSide
            switch transition.kind {
            case .unfold(let revealing):
                frame = FoldTimeline.unfold(at: elapsed, ratio: transition.ratio, revealing: revealing)
                other = revealing
            case .fold(let closing):
                frame = FoldTimeline.fold(at: elapsed, ratio: transition.ratio, closing: closing)
                other = closing
            }
            let usable = max(0, width - gap)
            let leading = (usable * CGFloat(frame.hinge)).rounded()
            var looks: [SplitSide: SplitLayout.Look] = [:]
            looks[other] = .init(blur: frame.otherBlur, opacity: frame.otherOpacity)
            looks[other.other] = .init(blur: frame.keptBlur, opacity: 1)
            return SplitLayout(gap: gap, usable: usable, leadingWidth: leading, trailingWidth: max(0, usable - leading),
                               isSplit: true, showsHinge: false, looks: looks,
                               seam: .init(x: leading + gap / 2, glow: frame.seamGlow, height: frame.seamHeight))
        }
        if isSplit {
            let usable = max(0, width - gap)
            let leading = (usable * CGFloat(ratio)).rounded()
            var looks: [SplitSide: SplitLayout.Look] = [:]
            if let foldPreview { looks[foldPreview.side] = .init(blur: 3 + 12 * foldPreview.depth, opacity: 1) }
            return SplitLayout(gap: gap, usable: usable, leadingWidth: leading, trailingWidth: max(0, usable - leading),
                               isSplit: true, showsHinge: true, looks: looks, seam: nil)
        }
        return SplitLayout(gap: 0, usable: width, leadingWidth: single == .leading ? width : 0,
                           trailingWidth: single == .trailing ? width : 0, isSplit: false, showsHinge: false, looks: [:], seam: nil)
    }
}

/// The surface at one moment.
public struct SplitLayout: Equatable, Sendable {
    public struct Look: Equatable, Sendable {
        public var blur: Double = 0
        public var opacity: Double = 1
    }

    public struct Seam: Equatable, Sendable {
        public var x: CGFloat
        public var glow: Double
        public var height: Double
    }

    public var gap: CGFloat
    /// The width the two pages share.
    public var usable: CGFloat
    public var leadingWidth: CGFloat
    public var trailingWidth: CGFloat
    public var isSplit: Bool
    public var showsHinge: Bool
    public var looks: [SplitSide: Look]
    public var seam: Seam?

    public var hingeX: CGFloat { leadingWidth + gap / 2 }

    public func look(_ side: SplitSide) -> Look { looks[side] ?? Look() }

    public func width(_ side: SplitSide) -> CGFloat { side == .leading ? leadingWidth : trailingWidth }
}
