import Foundation

public actor BatchUpdateCheckerActor {
    private let updater: SkillUpdaterActor
    private let maxConcurrent: Int

    public init(updater: SkillUpdaterActor, maxConcurrent: Int = 4) {
        self.updater = updater
        self.maxConcurrent = maxConcurrent
    }

    public func checkAll(skills: [Skill]) async throws -> [SkillIdentity: UpdateStatus] {
        var result: [SkillIdentity: UpdateStatus] = [:]
        // 分批扫描，保持 maxConcurrent
        var iterator = skills.makeIterator()
        var inFlight: [Task<(SkillIdentity, UpdateStatus), Error>] = []

        func dispatchNext() {
            guard let skill = iterator.next() else { return }
            let updater = self.updater
            inFlight.append(
                Task {
                    let status = try await updater.checkStatus(
                        name: skill.name, source: skill.source, canonical: skill.path
                    )
                    return (skill.id, status)
                })
        }

        for _ in 0..<min(maxConcurrent, skills.count) { dispatchNext() }

        while !inFlight.isEmpty {
            let task = inFlight.removeFirst()
            let (id, status) = try await task.value
            result[id] = status
            dispatchNext()
        }
        return result
    }
}
