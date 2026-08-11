import Foundation

// Mock/live switch. With BSAPIBaseURL empty in Info.plist (the default) the
// app runs fully offline on MockBountyAPI — the design-fidelity demo. Set it
// (e.g. https://api.bountysounds.com) plus BSTikTokClientKey to go live.
enum AppConfig {
    private static func plistString(_ key: String) -> String? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: key) as? String, !s.isEmpty else { return nil }
        return s
    }

    static var apiBaseURL: URL? { plistString("BSAPIBaseURL").flatMap(URL.init(string:)) }
    static var isLive: Bool { apiBaseURL != nil }

    static var tiktokClientKey: String? { plistString("BSTikTokClientKey") }

    // TikTok requires an https redirect; the backend bounces it into this scheme.
    static let oauthCallbackScheme = "bountysounds"
    static var oauthRedirectURI: String {
        plistString("BSTikTokRedirectURI")
            ?? apiBaseURL.map { $0.appendingPathComponent("v1/auth/tiktok/callback").absoluteString }
            ?? ""
    }

    static let sessionKeychainKey = "session-token"
}
