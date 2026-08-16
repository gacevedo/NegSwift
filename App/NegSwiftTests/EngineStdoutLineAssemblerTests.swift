//
//  EngineStdoutLineAssemblerTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

struct EngineStdoutLineAssemblerTests {
    @Test func reassemblesLineSplitAcrossChunks() {
        let payload = Data("{\"id\":\"1\",\"ok\":true}\n".utf8)
        for chunkSize in [1, 10, 25, payload.count] {
            let assembler = EngineStdoutLineAssembler()
            var lines: [Data] = []
            assembler.onLine = { lines.append($0) }

            var offset = 0
            while offset < payload.count {
                let end = min(offset + chunkSize, payload.count)
                assembler.append(payload[offset ..< end])
                offset = end
            }

            #expect(lines.count == 1)
            #expect(String(data: lines[0], encoding: .utf8) == "{\"id\":\"1\",\"ok\":true}")
        }
    }

    @Test func deliversMultipleLinesInOrder() {
        let assembler = EngineStdoutLineAssembler()
        var lines: [String] = []
        assembler.onLine = { line in
            lines.append(String(decoding: line, as: UTF8.self))
        }

        let payload = Data("{\"id\":\"a\"}\n{\"id\":\"b\"}\n".utf8)
        assembler.append(payload.prefix(8))
        assembler.append(payload.dropFirst(8))

        #expect(lines == ["{\"id\":\"a\"}", "{\"id\":\"b\"}"])
    }
}
