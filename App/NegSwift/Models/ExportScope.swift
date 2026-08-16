//
//  ExportScope.swift
//  NegSwift
//

import Foundation

enum ExportScope: Equatable, Sendable {
    case current
    case selected
    case all
}

struct BatchExportProgress {
    let scope: ExportScope
    let settings: ExportSettings
    var completed: Int
    var total: Int
    var currentName: String

    var statusText: String {
        guard total > 1 else { return settings.progressStatusText }
        let index = min(completed + 1, total)
        return "Exporting \(index) of \(total) — \(currentName)…"
    }
}

extension Array where Element == ScanFrame {
    func resolvingExportScope(
        _ scope: ExportScope,
        selectedFrameID: UUID?,
        selectedFrameIDs: Set<UUID> = []
    ) -> [ScanFrame] {
        let ids: Set<UUID> = switch scope {
        case .current:
            Set(selectedFrameID.map { [$0] } ?? [])
        case .selected:
            selectedFrameIDs.isEmpty
                ? Set(selectedFrameID.map { [$0] } ?? [])
                : selectedFrameIDs
        case .all:
            Set(map(\.id))
        }
        return filter { ids.contains($0.id) }
    }
}
