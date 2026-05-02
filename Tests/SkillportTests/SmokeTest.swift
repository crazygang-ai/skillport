import Testing

@Suite("Smoke")
struct SmokeTests {
    @Test("Truth is true")
    func truthIsTrue() {
        #expect(true)
    }
}
