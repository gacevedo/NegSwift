//
//  PreviewZoomMode.swift
//  NegSwift
//

import Foundation

enum PreviewZoomMode: String, Equatable {
    case fit
    case oneToOne

    var label: String {
        switch self {
        case .fit: "Fit"
        case .oneToOne: "1:1"
        }
    }

    mutating func toggle() {
        self = self == .fit ? .oneToOne : .fit
    }
}
