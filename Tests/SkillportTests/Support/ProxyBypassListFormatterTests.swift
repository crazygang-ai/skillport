import Testing

@testable import Skillport

@Suite("ProxyBypassListFormatter")
struct ProxyBypassListFormatterTests {
    @Test("parse accepts comma and newline separated entries")
    func parse() {
        let parsed = ProxyBypassListFormatter.parse("localhost, 127.0.0.1\n*.local,  ")

        #expect(parsed == ["localhost", "127.0.0.1", "*.local"])
    }

    @Test("string renders entries for Settings text field")
    func render() {
        let rendered = ProxyBypassListFormatter.string(from: ["localhost", "127.0.0.1"])

        #expect(rendered == "localhost, 127.0.0.1")
    }
}
