import CryptoKit
import DeviceCheck
import Foundation
import LocalAuthentication

// Face ID gate + App Attest for cash-out. The backend registers the key at
// POST /v1/me/attest and then requires assertions from it on
// POST /v1/me/payouts ("<keyId>:<assertion>" in X-Device-Attestation).
enum DeviceTrust {
    private static let keychainKey = "attest-key-id"

    // Face ID (or passcode fallback). Devices with no biometry configured
    // pass through so the beta isn't bricked on simulators.
    static func confirmOwner(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    // Register the App Attest key once, then produce a per-call assertion.
    // Simulators (unsupported) fall back to a marker the backend accepts only
    // for accounts with no registered key outside live mode.
    static func attestationHeader(baseURL: URL, token: String) async -> String {
        let service = DCAppAttestService.shared
        guard service.isSupported else { return "simulator:unsupported" }
        do {
            let keyId: String
            if let stored = Keychain.load(keychainKey) {
                keyId = stored
            } else {
                keyId = try await service.generateKey()
                let clientHash = Data(SHA256.hash(data: Data(token.utf8)))
                let attestation = try await service.attestKey(keyId, clientDataHash: clientHash)
                var request = URLRequest(url: baseURL.appendingPathComponent("v1/me/attest"))
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "keyId": keyId,
                    "attestation": attestation.base64EncodedString(),
                ])
                _ = try await URLSession.shared.data(for: request)
                Keychain.save(keyId, for: keychainKey)
            }
            let assertionHash = Data(SHA256.hash(data: Data("cash-out".utf8)))
            let assertion = try await service.generateAssertion(keyId, clientDataHash: assertionHash)
            return "\(keyId):\(assertion.base64EncodedString())"
        } catch {
            return "attest-failed:retry"
        }
    }
}
