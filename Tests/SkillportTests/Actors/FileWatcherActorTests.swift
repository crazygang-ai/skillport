import Foundation
import Testing

@testable import Skillport

@Suite("FileWatcherActor", .serialized)
struct FileWatcherActorTests {
    @Test("Emits event when a file is created under watched path")
    func emitsOnCreate() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let watcher = FileWatcherActor()
        let stream = await watcher.start(paths: [dir.url])
        defer { Task { await watcher.stop() } }

        let receivedTask = Task { () -> URL? in
            for await event in stream {
                if event.paths.contains(where: { $0.path.hasSuffix("/new.txt") }) {
                    return event.paths.first
                }
            }
            return nil
        }

        // 给 FSEvents 一点时间 attach
        try await Task.sleep(nanoseconds: 300_000_000)
        try "hi".write(
            to: dir.url.appendingPathComponent("new.txt"),
            atomically: true, encoding: .utf8)

        // 等待事件（5s deadline）
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if receivedTask.isCancelled == false, await !receivedTask.value.isNil() { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let url = await receivedTask.value
        #expect(url != nil)
    }

    @Test("stop() ends the stream")
    func stopEndsStream() async throws {
        let dir = try TempDir.create()
        defer { try? dir.cleanup() }
        let watcher = FileWatcherActor()
        let stream = await watcher.start(paths: [dir.url])
        await watcher.stop()
        var iter = stream.makeAsyncIterator()
        let next = await iter.next()
        #expect(next == nil)
    }
}

private extension Optional {
    func isNil() -> Bool { self == nil }
}
