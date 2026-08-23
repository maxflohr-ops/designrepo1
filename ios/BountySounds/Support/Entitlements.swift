import Foundation
import StoreKit
import SwiftUI

// Skin unlocks — non-consumable StoreKit 2 in-app purchases, one product per
// paid skin (`com.bountysounds.skin.<id>`).
//
// Pricing note carried over from docs/skins/FEASIBILITY.md §2: a $1 skin nets
// $0.85 under the Small Business Program. Skins are a retention and data
// instrument, not a revenue line — the money is the artist-side attention
// report. Don't let the catalog grow on the assumption it pays for itself.
//
// Not yet done (§6): server-side receipt validation. StoreKit's own
// verification is trusted here, which a jailbroken device can defeat.
@MainActor
final class EntitlementStore: ObservableObject {
    @Published private(set) var owned: Set<String> = []
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var purchasing: String?
    @Published private(set) var lastError: String?

    private var updatesTask: Task<Void, Never>?

    // Prototype builds (no BSAPIBaseURL, so the whole app is on mock fixtures
    // and no StoreKit products exist) treat every skin as owned so the demo is
    // walkable. A configured build never takes this path.
    private var prototypeUnlockAll: Bool { !AppConfig.isLive }

    init() {
        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                self?.apply(transaction)
                await transaction.finish()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit { updatesTask?.cancel() }

    func owns(_ skin: SkinDescriptor) -> Bool {
        guard let productID = skin.productID else { return true }
        return prototypeUnlockAll || owned.contains(productID)
    }

    // Real localized price once StoreKit answers; the catalog's "$1" until then.
    func priceLabel(for skin: SkinDescriptor) -> String {
        guard let productID = skin.productID else { return skin.priceLabel }
        return products[productID]?.displayPrice ?? skin.priceLabel
    }

    func loadProducts() async {
        let ids = SkinCatalog.all.compactMap(\.productID)
        guard !ids.isEmpty else { return }
        guard let loaded = try? await Product.products(for: ids) else { return }
        products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
    }

    func refreshEntitlements() async {
        var found: Set<String> = []
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if transaction.revocationDate == nil { found.insert(transaction.productID) }
        }
        owned = found
    }

    @discardableResult
    func purchase(_ skin: SkinDescriptor) async -> Bool {
        guard let productID = skin.productID else { return true }
        if owns(skin) { return true }
        guard let product = products[productID] else {
            lastError = "That skin isn't available right now."
            return false
        }

        purchasing = productID
        defer { purchasing = nil }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "That purchase couldn't be verified."
                    return false
                }
                apply(transaction)
                await transaction.finish()
                return true
            case .userCancelled:
                return false
            case .pending:
                lastError = "Waiting on approval for that purchase."
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    private func apply(_ transaction: StoreKit.Transaction) {
        if transaction.revocationDate == nil {
            owned.insert(transaction.productID)
        } else {
            owned.remove(transaction.productID)
        }
    }
}
