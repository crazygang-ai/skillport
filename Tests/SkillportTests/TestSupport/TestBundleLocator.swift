import Foundation

// Bundle.module is not generated for xcodegen Xcode test targets.
// Use Bundle(for:) with a marker class instead.
enum TestBundleLocator {
    static let bundle: Bundle = {
        class InternalMarker {}
        return Bundle(for: InternalMarker.self)
    }()
}
