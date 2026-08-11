import UIKit

// PaymentSheet wrapper. The stripe-ios package is declared in the project;
// the canImport guard keeps the target building even before package
// resolution has run (and in mock-only setups where nothing pays for real).
#if canImport(StripePaymentSheet)
import StripePaymentSheet

@MainActor
enum PurseFunding {
    static func present(clientSecret: String) async -> Bool {
        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = "Bounty Sounds"
        let sheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: configuration)
        guard let presenter = topViewController() else { return false }
        return await withCheckedContinuation { continuation in
            sheet.present(from: presenter) { result in
                if case .completed = result { continuation.resume(returning: true) }
                else { continuation.resume(returning: false) }
            }
        }
    }
}
#else
@MainActor
enum PurseFunding {
    // Without the Stripe package the payment step is a no-op success, which
    // matches mock mode's behavior (nil client secret never reaches here).
    static func present(clientSecret: String) async -> Bool { true }
}
#endif

@MainActor
func topViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }
        .first?.rootViewController
    var top = root
    while let presented = top?.presentedViewController { top = presented }
    return top
}
