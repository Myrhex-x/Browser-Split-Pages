//
//  FoldTimeline.swift
//  SplitPages
//
//  How the surface looks at each moment of an opening or a fold, as plain numbers: where the hinge
//  is, how out of focus each page is, and how bright the seam of light is. The view reads a frame
//  for every display refresh while a transition runs.
//

import Foundation

/// A CSS-style cubic Bézier timing curve, solved the way browsers solve them.
public struct UnitBezier: Sendable {
    private let ax, bx, cx, ay, by, cy: Double

    public init(_ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double) {
        cx = 3 * p1x; bx = 3 * (p2x - p1x) - cx; ax = 1 - cx - bx
        cy = 3 * p1y; by = 3 * (p2y - p1y) - cy; ay = 1 - cy - by
    }

    /// Fast out, long gentle settle: things moving into place.
    public static let expo = UnitBezier(0.16, 1, 0.3, 1)
    /// Color and opacity.
    public static let standard = UnitBezier(0.2, 0, 0, 1)

    public func callAsFunction(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        var t = x
        for _ in 0..<8 {
            let error = sampleX(t) - x
            if abs(error) < 1e-6 { return sampleY(t) }
            let slope = (3 * ax * t + 2 * bx) * t + cx
            if abs(slope) < 1e-6 { break }
            t -= error / slope
        }
        var low = 0.0, high = 1.0
        t = x
        while high - low > 1e-7 {
            let value = sampleX(t)
            if abs(value - x) < 1e-6 { break }
            if x > value { low = t } else { high = t }
            t = (low + high) / 2
        }
        return sampleY(t)
    }

    private func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
}

public enum FoldTimeline {
    public static let unfoldDuration = 0.82
    public static let foldDuration = 0.7

    public struct Frame: Equatable, Sendable {
        /// Where the hinge is, as the leading page's share of the width (1: it has all of it).
        public var hinge: Double
        /// The page that stays: how out of focus it is, in points of blur.
        public var keptBlur: Double
        /// The other page (arriving, or going): how out of focus, and how visible.
        public var otherBlur: Double
        public var otherOpacity: Double
        /// The seam of light: how bright, and how much of the height it covers (from the middle).
        public var seamGlow: Double
        public var seamHeight: Double
    }

    /// 0 before `from`, 1 after `to`, along `curve` between.
    public static func ramp(_ t: Double, _ from: Double, _ to: Double, _ curve: UnitBezier = .standard) -> Double {
        guard to > from else { return t >= to ? 1 : 0 }
        return curve((t - from) / (to - from))
    }

    /// Up over `rise`, down over `fall`.
    public static func bump(_ t: Double, rise: (Double, Double), fall: (Double, Double)) -> Double {
        min(ramp(t, rise.0, rise.1), 1 - ramp(t, fall.0, fall.1))
    }

    /// Opening: the page on screen makes room for the other side, which comes into focus.
    /// `revealing` is the side that arrives.
    public static func unfold(at t: Double, ratio: Double, revealing: SplitSide = .trailing) -> Frame {
        let move = ramp(t, 0.06, 0.64, .expo)
        return Frame(
            hinge: revealing == .trailing ? 1 - (1 - ratio) * move : ratio * move,
            keptBlur: 14 * bump(t, rise: (0, 0.2), fall: (0.36, 0.8)),
            otherBlur: 24 * (1 - ramp(t, 0.14, 0.76, .expo)),
            otherOpacity: ramp(t, 0.12, 0.52),
            seamGlow: bump(t, rise: (0, 0.16), fall: (0.44, 0.82)),
            seamHeight: ramp(t, 0, 0.34, .expo))
    }

    /// Folding: the closing page goes out of focus and away; the other takes the whole surface.
    public static func fold(at t: Double, ratio: Double, closing: SplitSide) -> Frame {
        let move = ramp(t, 0.04, 0.52, .expo)
        return Frame(
            hinge: closing == .trailing ? ratio + (1 - ratio) * move : ratio * (1 - move),
            keptBlur: 12 * bump(t, rise: (0, 0.18), fall: (0.32, 0.7)),
            otherBlur: 26 * ramp(t, 0, 0.32),
            otherOpacity: 1 - ramp(t, 0.06, 0.42),
            seamGlow: bump(t, rise: (0, 0.12), fall: (0.3, 0.62)),
            seamHeight: 1 - ramp(t, 0.3, 0.66))
    }
}

/// One of the two pages.
public enum SplitSide: Hashable, Sendable {
    case leading, trailing

    public var other: SplitSide { self == .leading ? .trailing : .leading }
}

/// Where the hinge goes as it's dragged: it settles on thirds and halves, and near an edge it offers
/// to fold that page away.
public enum SplitHingeMath {
    public static let snapPoints: [Double] = [1.0 / 3, 0.5, 2.0 / 3]
    public static let snapDistance = 0.012
    /// The hinge's whole travel while dragging.
    public static let travel: ClosedRange<Double> = 0.05...0.95
    /// Past this share from an edge, letting go folds that side away.
    public static let foldZone = 0.15
    /// Where the hinge comes to rest when let go outside the fold zone.
    public static let resting: ClosedRange<Double> = 0.2...0.8

    public struct Resolved: Equatable, Sendable {
        public var ratio: Double
        public var snapped: Double?
        public var folding: SplitSide?
        public var depth: Double
    }

    public static func resolve(_ raw: Double) -> Resolved {
        let ratio = min(max(raw, travel.lowerBound), travel.upperBound)
        if let point = snapPoints.first(where: { abs($0 - ratio) <= snapDistance }) {
            return Resolved(ratio: point, snapped: point, folding: nil, depth: 0)
        }
        if ratio < foldZone {
            return Resolved(ratio: ratio, snapped: nil, folding: .leading, depth: (foldZone - ratio) / (foldZone - travel.lowerBound))
        }
        if ratio > 1 - foldZone {
            return Resolved(ratio: ratio, snapped: nil, folding: .trailing, depth: (ratio - (1 - foldZone)) / (travel.upperBound - (1 - foldZone)))
        }
        return Resolved(ratio: ratio, snapped: nil, folding: nil, depth: 0)
    }

    public static func settle(_ ratio: Double) -> Double {
        min(max(ratio, resting.lowerBound), resting.upperBound)
    }

    /// "60 · 40": how the room is shared, for the label beside the hinge.
    public static func label(_ ratio: Double) -> String {
        let leading = Int((ratio * 100).rounded())
        return "\(leading) · \(100 - leading)"
    }
}
