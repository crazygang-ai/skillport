import CoreServices
import Foundation

public struct FileEvent: Sendable {
    public let paths: [URL]
    public let timestamp: Date
}

public actor FileWatcherActor {
    private var fsStream: FSEventStreamRef?
    private var continuation: AsyncStream<FileEvent>.Continuation?

    public init() {}

    public func start(paths: [URL], latency: TimeInterval = 0.2) -> AsyncStream<FileEvent> {
        stop()
        let (asyncStream, cont) = AsyncStream<FileEvent>.makeStream()
        self.continuation = cont

        let pathsCF = paths.map { $0.path as CFString } as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info else { return }
            let actor = Unmanaged<FileWatcherActor>.fromOpaque(info).takeUnretainedValue()
            let rawPaths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            let urls = (0..<numEvents).map { i in
                URL(fileURLWithPath: String(cString: rawPaths[i]))
            }
            let event = FileEvent(paths: urls, timestamp: Date())
            Task { await actor.emit(event) }
        }
        guard
            let createdStream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                pathsCF,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                FSEventStreamCreateFlags(
                    kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
                )
            )
        else {
            cont.finish()
            return asyncStream
        }
        self.fsStream = createdStream
        FSEventStreamSetDispatchQueue(createdStream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(createdStream)
        return asyncStream
    }

    public func stop() {
        if let s = fsStream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            fsStream = nil
        }
        continuation?.finish()
        continuation = nil
    }

    private func emit(_ event: FileEvent) {
        continuation?.yield(event)
    }
}
