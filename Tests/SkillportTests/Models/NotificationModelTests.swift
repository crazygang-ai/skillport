import Testing

@testable import Skillport

@Suite("NotificationModel")
@MainActor
struct NotificationModelTests {
    @Test("post adds a toast at the end; id uniqueness")
    func post() {
        let m = NotificationModel()
        m.post(.init(level: .info, message: "hi"))
        m.post(.init(level: .error, message: "boom"))
        #expect(m.toasts.count == 2)
        #expect(Set(m.toasts.map(\.id)).count == 2)
    }

    @Test("dismiss removes a toast by id") func dismiss() {
        let m = NotificationModel()
        let t = Toast(level: .warning, message: "w")
        m.post(t)
        m.dismiss(id: t.id)
        #expect(m.toasts.isEmpty)
    }
}
