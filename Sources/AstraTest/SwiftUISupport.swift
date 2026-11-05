import SwiftUI

#if os(iOS)
import UIKit
private struct PrivateMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        v.astraPrivate = true
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
#elseif os(macOS)
import AppKit
private final class PrivateNSView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
private struct PrivateMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = PrivateNSView()
        v.astraPrivate = true
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

public extension View {
    /// Blacks this view out in report screenshots, for example a message body or an account number.
    /// Secure fields are always hidden; use this for anything else private.
    func astraPrivate(_ isPrivate: Bool = true) -> some View {
        overlay(Group { if isPrivate { PrivateMarker().allowsHitTesting(false).accessibilityHidden(true) } })
    }
}

/// Shows whether Astra Test is running and why, for a test-build Settings or About screen.
///
/// ```swift
/// Section("About") { AstraTestStatus() }
/// ```
public struct AstraTestStatus: View {
    @State private var running = AstraTest.isRunning
    @State private var status = AstraTest.status
    @State private var update = AstraTest.updateAvailable

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Astra Test")
                Spacer()
                Text(running ? "On" : "Off").foregroundColor(running ? .green : .secondary)
            }
            Text(status).font(.caption).foregroundColor(.secondary)
            if let update {
                Text("Update available: AstraTest \(update)").font(.caption).foregroundColor(.orange)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AstraTest.statusDidChange).receive(on: RunLoop.main)) { _ in
            running = AstraTest.isRunning
            status = AstraTest.status
            update = AstraTest.updateAvailable
        }
    }
}
