import AuthenticationServices
import UIKit

// TikTok Login Kit over ASWebAuthenticationSession. Flow: authorize on
// tiktok.com → redirect to the backend's https callback → 302 into
// bountysounds://oauth?code=… → exchange the code at POST /v1/auth/tiktok.
@MainActor
final class TikTokAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum AuthError: Error { case notConfigured, cancelled, noCode, badResponse }

    private var session: ASWebAuthenticationSession?

    func authorize() async throws -> String {
        guard let clientKey = AppConfig.tiktokClientKey else { throw AuthError.notConfigured }
        var comps = URLComponents(string: "https://www.tiktok.com/v2/auth/authorize/")!
        comps.queryItems = [
            URLQueryItem(name: "client_key", value: clientKey),
            URLQueryItem(name: "scope", value: "user.info.basic,user.info.stats,video.list,video.publish"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: AppConfig.oauthRedirectURI),
            URLQueryItem(name: "state", value: UUID().uuidString),
        ]
        let url = comps.url!

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: AppConfig.oauthCallbackScheme
            ) { callbackURL, error in
                if error != nil { continuation.resume(throwing: AuthError.cancelled); return }
                guard let callbackURL,
                      let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value
                else { continuation.resume(throwing: AuthError.noCode); return }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    // Exchange the OAuth code for a Bounty Sounds session token.
    static func exchange(code: String, role: String, baseURL: URL) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/auth/tiktok"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "role": role])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = body["token"] as? String
        else { throw AuthError.badResponse }
        return token
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
