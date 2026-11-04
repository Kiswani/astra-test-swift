import SwiftUI
import AstraTest

@main
struct DemoApp: App {
    init() {
        AstraTest.start(key: ProcessInfo.processInfo.environment["ASTRA_KEY"] ?? "pk_test_f2463b056a52fafa6684fe6e")
        AstraTest.identify(email: "sdk-e2e@astratest.dev", name: "Apple demo")
        AstraTest.setScreen("Checkout")
    }
    var body: some Scene {
        WindowGroup("Checkout") {
            CheckoutView()
                .onAppear {
                    if ProcessInfo.processInfo.arguments.contains("-astraOpen") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { AstraTest.showReport() }
                    }
                }
        }
    }
}

struct CheckoutView: View {
    @State private var code = "WELCOME20"
    @State private var password = "secret-password"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SABLE").font(.title2).tracking(4)
            HStack { Text("Ceramic pour-over set"); Spacer(); Text("AED 240.00") }
            HStack { Text("Single-origin beans"); Spacer(); Text("AED 65.00") }
            TextField("Promo code", text: $code).textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
            HStack { Text("Total").bold(); Spacer(); Text("AED 304.80").bold() }
            Button("Pay AED 304.80") { print("Pay tapped; total still 304.80") }.buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(24)
        .task {
            // A request for the report to show.
            _ = try? await URLSession.shared.data(from: URL(string: "https://astratest.dev/v1/health")!)
            _ = try? await URLSession.shared.data(from: URL(string: "https://example.com/api/promo?code=WELCOME20")!)
        }
    }
}
