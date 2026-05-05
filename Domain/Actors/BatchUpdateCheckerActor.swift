import Foundation

public actor BatchUpdateCheckerActor {
    private let checkStatus: @Sendable (Skill) async throws -> UpdateStatus
    private let maxConcurrent: Int

    public init(updater: SkillUpdaterActor, maxConcurrent: Int = 4) {
        self.checkStatus = { skill in
            try await updater.checkStatus(
                name: skill.name, source: skill.source, canonical: skill.path
            )
        }
        self.maxConcurrent = max(1, maxConcurrent)
    }

    public init(
        maxConcurrent: Int = 4,
        checkStatus: @escaping @Sendable (Skill) async throws -> UpdateStatus
    ) {
        self.checkStatus = checkStatus
        self.maxConcurrent = max(1, maxConcurrent)
    }

    public func checkAll(skills: [Skill]) async throws -> [SkillIdentity: UpdateStatus] {
        try await withThrowingTaskGroup(of: (SkillIdentity, UpdateStatus).self) { group in
            var result: [SkillIdentity: UpdateStatus] = [:]
            var iterator = skills.makeIterator()
            let limit = min(maxConcurrent, skills.count)

            func dispatchNext() -> Bool {
                guard let skill = iterator.next() else { return false }
                let checkStatus = self.checkStatus
                group.addTask {
                    let status = try await checkStatus(skill)
                    return (skill.id, status)
                }
                return true
            }

            for _ in 0..<limit {
                _ = dispatchNext()
            }
            while let (id, status) = try await group.next() {
                result[id] = status
                _ = dispatchNext()
            }
            return result
        }
    }
}
