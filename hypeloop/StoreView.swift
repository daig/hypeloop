import SwiftUI
import StoreKit

struct StoreView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeService = StoreService.shared
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if storeService.isLoading {
                    ProgressView("Loading products...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                } else if let error = storeService.loadingError {
                    VStack(spacing: 16) {
                        Text(error)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Button(action: {
                            Task {
                                await storeService.loadProducts()
                            }
                        }) {
                            Text("Try Again")
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(red: 0.2, green: 0.2, blue: 0.3))
                                )
                        }
                    }
                    .padding()
                } else if storeService.products.isEmpty {
                    Text("No products available")
                        .foregroundColor(.white)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            ForEach(storeService.products) { product in
                                ProductCard(
                                    product: product,
                                    isPurchasing: storeService.purchasingProduct?.id == product.id,
                                    action: {
                                        Task {
                                            do {
                                                try await storeService.purchase(product)
                                                // Close the sheet after successful purchase
                                                dismiss()
                                            } catch {
                                                errorMessage = error.localizedDescription
                                                showingError = true
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Buy Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .alert("Purchase Error", isPresented: $showingError, actions: {
                Button("OK", role: .cancel) { }
            }, message: {
                Text(errorMessage ?? "An unknown error occurred")
            })
        }
    }
}

struct ProductCard: View {
    let product: Product
    let isPurchasing: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(product.description)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if isPurchasing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(product.displayPrice)
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.2, opacity: 0.7))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isPurchasing)
    }
} 