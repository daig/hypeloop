import StoreKit
import SwiftUI

@MainActor
class StoreService: ObservableObject {
    static let shared = StoreService()
    private let authService = AuthService.shared
    
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasingProduct: Product?
    @Published private(set) var isLoading = true
    @Published private(set) var loadingError: String?
    
    // Product IDs should match both StoreKit config and App Store Connect
    private let productIdentifiers = [
        "com.hypeloop.credits.100",
        "com.hypeloop.credits.500",
        "com.hypeloop.credits.1000"
    ]
    
    private var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
    
    private init() {
        // Start listening for transactions as soon as the app launches
        Task {
            await startTransactionListener()
        }
        
        // Load products
        Task {
            await loadProducts()
        }
    }
    
    private func startTransactionListener() async {
        do {
            print("🛍️ Environment: \(isTestFlight ? "TestFlight" : "Debug")")
            if isTestFlight {
                print("🛍️ Sandbox testing enabled - you can use your sandbox Apple ID for both auth and purchases")
            }
            
            // Check if the user is signed in to their App Store account
            try await AppStore.sync()
            print("✅ App Store account sync successful")
            
            // Listen for transactions from the App Store
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    // Handle successful purchase
                    let credits = creditsForProduct(transaction.productID)
                    if credits > 0 {
                        await authService.addCredits(credits)
                    }
                    
                    // Finish the transaction
                    await transaction.finish()
                    print("✅ Transaction completed successfully: \(transaction.productID)")
                    
                case .unverified(_, let error):
                    print("❌ Transaction unverified: \(error)")
                    print("❌ If in TestFlight, make sure you're using a sandbox account for both auth and purchases")
                }
            }
        } catch {
            print("❌ Failed to start transaction listener: \(error.localizedDescription)")
            if isTestFlight {
                print("❌ Make sure you're signed in with a sandbox account that has Sign in with Apple enabled")
            }
        }
    }
    
    func loadProducts() async {
        isLoading = true
        loadingError = nil
        
        do {
            print("🛍️ Environment: \(isTestFlight ? "TestFlight" : "Debug")")
            print("🛍️ Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
            print("🛍️ App Store Receipt: \(Bundle.main.appStoreReceiptURL?.path ?? "none")")
            print("🛍️ Requesting products with IDs: \(productIdentifiers)")
            
            // Request products from the App Store
            let products = try await Product.products(for: productIdentifiers)
            print("🛍️ Received \(products.count) products from StoreKit")
            
            // Log each product's details
            for product in products {
                print("🛍️ Found product: \(product.id) - \(product.displayName) - \(product.displayPrice)")
            }
            
            self.products = products
            
            if products.isEmpty {
                print("🛍️ No products were returned from StoreKit")
                if !isTestFlight {
                    loadingError = """
                        No products available. Please ensure that:
                        1. You have selected Products.storekit in your scheme settings
                        2. You are running the app in debug mode
                        
                        Go to Product > Scheme > Edit Scheme > Run > Options
                        Set "StoreKit Configuration" to Products.storekit
                        """
                } else {
                    loadingError = """
                        No products available. This could be because:
                        1. Products aren't configured in App Store Connect
                        2. You're not signed in with a sandbox account
                        3. The app's bundle identifier doesn't match
                        
                        Current Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")
                        
                        For TestFlight testing, make sure to:
                        1. Set up products in App Store Connect
                        2. Use a sandbox tester account
                        3. Wait for products to sync (can take a few minutes)
                        4. Check that In-App Purchase capability is enabled
                        """
                }
            }
        } catch {
            print("🛍️ Failed to load products: \(error)")
            print("🛍️ Error details: \(String(describing: error))")
            
            if !isTestFlight {
                loadingError = """
                    Failed to load products. Please ensure that:
                    1. You have selected Products.storekit in your scheme settings
                    2. You are running the app in debug mode
                    
                    Error: \(error.localizedDescription)
                    """
            } else {
                loadingError = """
                    Failed to load products. This could be because:
                    1. No internet connection
                    2. App Store services are unavailable
                    3. You need to sign in with a sandbox account
                    
                    Error: \(error.localizedDescription)
                    """
            }
        }
        
        isLoading = false
    }
    
    func purchase(_ product: Product) async throws {
        purchasingProduct = product
        defer { purchasingProduct = nil }
        
        do {
            print("🛍️ Starting purchase for: \(product.id)")
            print("🛍️ Environment: \(isTestFlight ? "TestFlight" : "Debug")")
            if isTestFlight {
                print("ℹ️ Make sure you're using the same sandbox account for auth and purchases")
            }
            
            try await AppStore.sync()
            
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    print("✅ Purchase verified for: \(product.id)")
                    let credits = creditsForProduct(product.id)
                    if credits > 0 {
                        await authService.addCredits(credits)
                        print("✅ Added \(credits) credits to user account")
                    }
                    await transaction.finish()
                    
                case .unverified(_, let error):
                    print("❌ Purchase verification failed: \(error)")
                    throw error
                }
                
            case .userCancelled:
                print("ℹ️ User cancelled the purchase")
                throw StoreKitError.userCancelled
                
            case .pending:
                print("ℹ️ Purchase is pending")
                
            @unknown default:
                break
            }
        } catch {
            print("❌ Purchase failed: \(error)")
            if case StoreKitError.userCancelled = error {
                throw error
            } else if case StoreKitError.notEntitled = error {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Please sign in to your App Store account to make purchases"])
            } else {
                throw error
            }
        }
    }
    
    private func creditsForProduct(_ productId: String) -> Int {
        switch productId {
        case "com.hypeloop.credits.100":
            return 100
        case "com.hypeloop.credits.500":
            return 500
        case "com.hypeloop.credits.1000":
            return 1000
        default:
            return 0
        }
    }
} 