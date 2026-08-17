//
//  ExportScopeTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

struct ExportScopeTests {
  private func makeFrames() -> (frames: [ScanFrame], ids: [UUID]) {
    let idA = UUID()
    let idB = UUID()
    let idC = UUID()
    let frames = [
      ScanFrame(id: idA, url: URL(fileURLWithPath: "/strip/a.tif"), path: "/strip/a.tif", name: "a.tif"),
      ScanFrame(id: idB, url: URL(fileURLWithPath: "/strip/b.tif"), path: "/strip/b.tif", name: "b.tif"),
      ScanFrame(id: idC, url: URL(fileURLWithPath: "/strip/c.tif"), path: "/strip/c.tif", name: "c.tif"),
    ]
    return (frames, [idA, idB, idC])
  }

  @Test func currentScopeReturnsPrimarySelectionInStripOrder() {
    let (frames, ids) = makeFrames()
    let resolved = frames.resolvingExportScope(.current, selectedFrameID: ids[1])
    #expect(resolved.map(\.name) == ["b.tif"])
  }

  @Test func allScopeReturnsEveryFrameInStripOrder() {
    let (frames, ids) = makeFrames()
    let resolved = frames.resolvingExportScope(.all, selectedFrameID: ids[2])
    #expect(resolved.map(\.name) == ["a.tif", "b.tif", "c.tif"])
  }

  @Test func selectedScopeFallsBackToPrimaryWhenEmpty() {
    let (frames, ids) = makeFrames()
    let resolved = frames.resolvingExportScope(.selected, selectedFrameID: ids[0], selectedFrameIDs: [])
    #expect(resolved.map(\.name) == ["a.tif"])
  }

  @Test func selectedScopeUsesExplicitSelectionSetInStripOrder() {
    let (frames, ids) = makeFrames()
    let resolved = frames.resolvingExportScope(
      .selected,
      selectedFrameID: ids[0],
      selectedFrameIDs: [ids[2], ids[0]]
    )
    #expect(resolved.map(\.name) == ["a.tif", "c.tif"])
  }

  @Test func batchProgressStatusTextForSingleFrameUsesSettingsText() {
    let progress = BatchExportProgress(
      scope: .current,
      settings: .quickExport,
      completed: 0,
      total: 1,
      currentName: "a.tif"
    )
    #expect(progress.statusText == ExportSettings.quickExport.progressStatusText)
  }

  @Test func batchProgressStatusTextForBatchShowsIndexAndName() {
    let progress = BatchExportProgress(
      scope: .all,
      settings: .quickExport,
      completed: 2,
      total: 5,
      currentName: "scan_003.tif"
    )
    #expect(progress.statusText == "Exporting 3 of 5 — scan_003.tif…")
  }

  @Test func availableScopesOmitsSelectedUntilMultiSelect() {
    #expect(ExportScope.availableScopes(selectionCount: 1) == [.current, .all])
    #expect(ExportScope.availableScopes(selectionCount: 2) == [.current, .selected, .all])
  }

  @Test func pickerLabelsIncludeCounts() {
    #expect(ExportScope.all.pickerLabel(selectionCount: 0, frameCount: 12) == "All (12)")
    #expect(ExportScope.selected.pickerLabel(selectionCount: 3, frameCount: 12) == "Selected (3)")
  }

  @Test @MainActor func defaultExportScopeUsesCurrentUntilMultiSelect() {
    let session = EngineSession.preview
    #expect(session.exportSelectionCount == 1)
    #expect(session.defaultExportScope == .current)
  }

  @Test @MainActor func defaultExportScopeUsesSelectedWhenMultiSelect() {
    let session = EngineSession.preview
    session.setFilmStripSelectionForTests(
      primary: session.frames[0].id,
      ids: Set(session.frames.map(\.id))
    )
    #expect(session.exportSelectionCount == 2)
    #expect(session.defaultExportScope == .selected)
    #expect(session.hasMultiExportSelection)
  }

  @Test @MainActor func exportSelectedFrameIDsReflectsFilmStripSelection() {
    let session = EngineSession.preview
    session.setFilmStripSelectionForTests(
      primary: session.frames[0].id,
      ids: [session.frames[0].id, session.frames[1].id]
    )
    #expect(session.exportSelectedFrameIDs.count == 2)
    #expect(session.frames(for: .selected).map(\.name) == ["a.tif", "b.tif"])
  }

  @Test @MainActor func engineSessionFramesForAllScope() {
    let session = EngineSession.preview
    #expect(session.frames(for: .all).map(\.name) == ["a.tif", "b.tif"])
    #expect(session.frames(for: .current).map(\.name) == ["a.tif"])
  }
}
