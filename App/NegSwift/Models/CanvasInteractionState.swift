//
//  CanvasInteractionState.swift
//  NegSwift
//

import CoreGraphics
import Foundation
import Observation

/// Canvas pan/zoom position — `@Observable` so mutations re-render across gesture events.
@MainActor
@Observable
final class CanvasInteractionState {
    /// Top-left of the image in viewport coordinates.
    var contentOffset: CGPoint = .zero
    var panDragStartOffset: CGPoint = .zero
    var isPanDragging = false
}
