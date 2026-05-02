import Foundation
import Testing

@testable import Skillport

@Suite("TempDir")
struct TempDirTests {
    @Test("Creates a unique directory on disk")
    func createsDirectory() throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dir.url.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test("Two TempDirs are distinct")
    func distinct() throws {
        let a = try TempDir.create()
        let b = try TempDir.create()
        defer {
            try? a.cleanup()
            try? b.cleanup()
        }
        #expect(a.url != b.url)
    }

    @Test("cleanup removes the directory")
    func cleanupRemoves() throws {
        let dir = try TempDir.create()
        let path = dir.url.path
        try dir.cleanup()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("writing and reading a file inside TempDir")
    func writeAndRead() throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let file = dir.url.appendingPathComponent("hello.txt")
        try "hi".write(to: file, atomically: true, encoding: .utf8)
        let back = try String(contentsOf: file, encoding: .utf8)
        #expect(back == "hi")
    }
}
