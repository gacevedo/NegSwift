//
//  NormalizedRectTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

struct NormalizedRectTests {
    @Test func centeredRespectsAspectRatio() {
        let rect = NormalizedRect.centered(ratioLabel: "3:2", imageAspect: 1.5)
        #expect(rect.width > 0.9)
        #expect(rect.height > 0.9)
    }

    @Test func clampedKeepsRectInsideUnitSquare() {
        let rect = NormalizedRect(x1: -0.2, y1: 0, x2: 1.2, y2: 1).clamped()
        #expect(rect.x1 >= 0)
        #expect(rect.y1 >= 0)
        #expect(rect.x2 <= 1)
        #expect(rect.y2 <= 1)
    }

    @Test func rotatedQuarterTurnSwapsNormalizedCorners() {
        let rect = NormalizedRect(x1: 0.1, y1: 0.2, x2: 0.9, y2: 0.8)
        let rotated = rect.rotated(quarterTurnsCCW: 1)
        #expect(rotated.width > 0)
        #expect(rotated.height > 0)
        #expect(rotated.x1 >= 0)
        #expect(rotated.y2 <= 1)
    }

    @Test func mirroredMatchesNegPyHorizontalAndVertical() {
        let rect = NormalizedRect(x1: 0.1, y1: 0.2, x2: 0.5, y2: 0.7)
        let horizontal = rect.mirrored(horizontal: true)
        #expect(horizontal.x1 == 0.5)
        #expect(horizontal.y1 == 0.2)
        #expect(horizontal.x2 == 0.9)
        #expect(horizontal.y2 == 0.7)

        let vertical = rect.mirrored(horizontal: false)
        #expect(vertical.x1 == 0.1)
        #expect(abs(vertical.y1 - 0.3) < 1e-12)
        #expect(vertical.x2 == 0.5)
        #expect(vertical.y2 == 0.8)
    }

    @Test func fromFlatValueParsesFourDoubles() {
        let rect = NormalizedRect.fromFlatValue([0.1, 0.2, 0.9, 0.85])
        #expect(rect?.x1 == 0.1)
        #expect(rect?.y2 == 0.85)
    }

    @Test func closestFilmAspectRatioLabelMatchesLandscapeFrame() {
        let rect = NormalizedRect(x1: 0.1, y1: 0.15, x2: 0.9, y2: 0.85)
        #expect(rect.closestFilmAspectRatioLabel(imageAspect: 1.5) == "3:2")
    }

    @Test func closestFilmAspectRatioLabelFallsBackToFreeForOddShapes() {
        let rect = NormalizedRect(x1: 0.05, y1: 0.4, x2: 0.95, y2: 0.55)
        #expect(rect.closestFilmAspectRatioLabel(imageAspect: 1.0) == "Free")
    }

    @Test func canonicalMapsInstagramPortraitAndLandscapeRatios() {
        #expect(CropAspectRatio.canonical("4:5") == .r4x5)
        #expect(CropAspectRatio.canonical("9:16") == .r9x16)
        #expect(CropAspectRatio.canonical("5:4") == .r5x4)
        #expect(CropAspectRatio.canonical("16:9") == .r16x9)
        #expect(CropAspectRatio.canonical("1.91:1") == .r191x100)
        #expect(CropAspectRatio.canonical("100:191") == .r191x100)
    }

    @Test func centeredInstagramPortraitRatiosAreTallerThanWide() {
        let imageAspect = 1.5
        let portraitFeed = NormalizedRect.centered(ratioLabel: "4:5", imageAspect: imageAspect)
        #expect(portraitFeed.height > portraitFeed.width)
        let pixelAspect = (portraitFeed.width / portraitFeed.height) * imageAspect
        #expect(abs(pixelAspect - 4.0 / 5.0) < 1e-6)

        let stories = NormalizedRect.centered(ratioLabel: "9:16", imageAspect: imageAspect)
        #expect(stories.height > stories.width)
    }

    @Test func centeredPrintRatioStaysLandscapeOnWideScan() {
        let imageAspect = 1.5
        let rect = NormalizedRect.centered(ratioLabel: "5:4", imageAspect: imageAspect)
        let pixelAspect = (rect.width / rect.height) * imageAspect
        #expect(abs(pixelAspect - 5.0 / 4.0) < 1e-6)
    }

    @Test func instagramRatiosShowPickerHints() {
        #expect(CropAspectRatio.r1x1.pickerLabel == "1:1 · Instagram")
        #expect(CropAspectRatio.r4x5.pickerLabel == "4:5 · Instagram")
        #expect(CropAspectRatio.r9x16.pickerLabel == "9:16 · Instagram")
        #expect(CropAspectRatio.r191x100.pickerLabel == "1.91:1 · Instagram")
        #expect(CropAspectRatio.r5x4.pickerLabel == "5:4")
        #expect(CropAspectRatio.r3x2.pickerLabel == "3:2")
    }
}
