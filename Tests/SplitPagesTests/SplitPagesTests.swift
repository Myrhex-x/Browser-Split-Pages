//
//  SplitPagesTests.swift
//  SplitPages
//

import Foundation
import Testing
@testable import SplitPages

struct FoldTimelineTests {
    @Test func opensFromOnePageToTheSplit() {
        let start = FoldTimeline.unfold(at: 0, ratio: 0.5)
        #expect(start.hinge == 1)
        #expect(start.keptBlur == 0)
        #expect(start.otherOpacity == 0)
        #expect(start.seamGlow == 0)

        let middle = FoldTimeline.unfold(at: 0.28, ratio: 0.5)
        #expect(middle.hinge < 1 && middle.hinge > 0.5)
        #expect(middle.keptBlur > 8)
        #expect(middle.seamGlow > 0.9)

        let end = FoldTimeline.unfold(at: FoldTimeline.unfoldDuration, ratio: 0.5)
        #expect(abs(end.hinge - 0.5) < 0.001)
        #expect(end.keptBlur < 0.01 && end.otherBlur < 0.01)
        #expect(end.otherOpacity == 1)
        #expect(end.seamGlow < 0.01)
    }

    @Test func opensTheLeadingSideFromTheLeft() {
        #expect(FoldTimeline.unfold(at: 0, ratio: 0.5, revealing: .leading).hinge == 0)
        #expect(abs(FoldTimeline.unfold(at: 1, ratio: 0.5, revealing: .leading).hinge - 0.5) < 0.001)
    }

    @Test func foldsTowardTheSideThatGoes() {
        #expect(abs(FoldTimeline.fold(at: 1, ratio: 0.4, closing: .trailing).hinge - 1) < 0.001)
        #expect(abs(FoldTimeline.fold(at: 1, ratio: 0.4, closing: .leading).hinge) < 0.001)
        let start = FoldTimeline.fold(at: 0, ratio: 0.4, closing: .trailing)
        #expect(start.hinge == 0.4)
        #expect(start.otherOpacity == 1)
        #expect(start.seamHeight == 1)
    }

    @Test func solvesCurvesLikeABrowser() {
        #expect(UnitBezier.expo(0) == 0)
        #expect(abs(UnitBezier.expo(1) - 1) < 1e-6)
        #expect(UnitBezier.expo(0.5) > 0.9)
        #expect(abs(UnitBezier(0.25, 0.25, 0.75, 0.75)(0.3) - 0.3) < 1e-4)
    }
}

struct SplitHingeMathTests {
    @Test func settlesOnThirdsAndHalves() {
        #expect(SplitHingeMath.resolve(0.505).snapped == 0.5)
        #expect(SplitHingeMath.resolve(0.34).ratio == 1.0 / 3)
        #expect(SplitHingeMath.resolve(0.42).snapped == nil)
    }

    @Test func offersToFoldNearAnEdge() {
        #expect(SplitHingeMath.resolve(0.1).folding == .leading)
        let trailing = SplitHingeMath.resolve(1.2)
        #expect(trailing.ratio == 0.95)
        #expect(trailing.folding == .trailing)
        #expect(trailing.depth == 1)
        #expect(SplitHingeMath.resolve(0.3).folding == nil)
    }

    @Test func comesToRestWithinReach() {
        #expect(SplitHingeMath.settle(0.1) == 0.2)
        #expect(SplitHingeMath.settle(0.9) == 0.8)
        #expect(SplitHingeMath.label(0.6) == "60 · 40")
    }
}

@MainActor
struct SplitPagesStateTests {
    private func state() -> SplitPagesState {
        let state = SplitPagesState()
        state.animates = false
        return state
    }

    @Test func opensAndFoldsBack() {
        let state = state()
        var folded: [SplitSide] = []
        state.onFold = { folded.append($0) }
        state.unfold()
        #expect(state.isSplit)
        #expect(state.focused == .trailing)
        state.toggle()
        #expect(!state.isSplit)
        #expect(state.single == .trailing)
        #expect(folded == [.leading])
    }

    @Test func laysThePagesOut() {
        let state = state()
        let one = state.layout(width: 1000, gap: 8)
        #expect(one.leadingWidth == 1000 && one.trailingWidth == 0)
        state.unfold()
        state.ratio = 0.25
        let two = state.layout(width: 1008, gap: 8)
        #expect(two.leadingWidth == 250 && two.trailingWidth == 750)
        #expect(two.hingeX == 254)
        #expect(two.showsHinge)
    }

    @Test func blursTheMovingPagesMidway() throws {
        let state = SplitPagesState()
        state.unfold()
        let transition = try #require(state.transition)
        let middle = state.layout(width: 1000, gap: 8, at: transition.start.addingTimeInterval(0.3))
        #expect(middle.look(.leading).blur > 8)
        #expect(middle.seam != nil)
        #expect(!middle.showsHinge)
    }
}
