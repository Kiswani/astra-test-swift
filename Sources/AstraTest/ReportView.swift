import SwiftUI

/// The report sheet, shared by iOS and macOS.
final class ReportModel: ObservableObject {
    @Published var text = ""
    @Published var element: PickedElement?
    @Published var sending = false
    @Published var error: String?
    @Published var sent: AstraTest.SentReport?
    let screenshot: Data?
    var onPick: (() -> Void)?
    var onClose: (() -> Void)?
    init(screenshot: Data?) { self.screenshot = screenshot }

    func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 3, !sending else { return }
        sending = true; error = nil
        Sender.send(description: t, severity: nil, element: element, screenshot: screenshot) { [weak self] r in
            guard let self else { return }
            self.sending = false
            switch r {
            case .success(let s): self.sent = s
            case .failure(let e): self.error = e.localizedDescription
            }
        }
    }
}

struct ReportView: View {
    @ObservedObject var model: ReportModel
    private let cobalt = Color(red: 0.184, green: 0.333, blue: 0.831)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.sent == nil ? "Report an issue" : "Thanks").font(.headline)
                Spacer()
                Button(model.sent == nil ? "Cancel" : "Done") { model.onClose?() }.buttonStyle(.borderless)
            }
            if let s = model.sent {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Sent as \(s.ref)", systemImage: "checkmark.circle.fill").foregroundColor(.green).font(.body.weight(.semibold))
                    Text("We'll let you know when it's fixed.").foregroundColor(.secondary).font(.subheadline)
                }
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What's wrong? Point at it").font(.caption).foregroundColor(.secondary)
                    HStack {
                        Text(model.element?.selector ?? "Nothing selected").font(.system(.footnote, design: .monospaced)).lineLimit(1)
                            .foregroundColor(model.element == nil ? .secondary : cobalt)
                        Spacer()
                        Button(model.element == nil ? "Point at it" : "Change") { model.onPick?() }.font(.footnote)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(cobalt.opacity(0.08)))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("What happened?").font(.caption).foregroundColor(.secondary)
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $model.text).frame(minHeight: 96).padding(4)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))
                        if model.text.isEmpty { Text("Say it in your own words").foregroundColor(.secondary.opacity(0.7)).padding(10).allowsHitTesting(false) }
                    }
                }
                Text(captured).font(.caption).foregroundColor(.secondary)
                if let e = model.error { Text(e).font(.footnote).foregroundColor(.red) }
                Button(action: model.send) {
                    HStack { Spacer(); Text(model.sending ? "Sending…" : "Send report").fontWeight(.semibold); Spacer() }.padding(.vertical, 10)
                }
                .buttonStyle(.plain).foregroundColor(.white)
                .background(RoundedRectangle(cornerRadius: 10).fill(cobalt.opacity(model.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 && !model.sending ? 1 : 0.4)))
                .disabled(model.sending)
            }
        }
        .padding(18)
    }

    private var captured: String {
        var parts: [String] = []
        if model.screenshot != nil { parts.append("Screenshot") }
        let n = NetworkCapture.calls.all().count, l = LogCapture.shared.lines.all().count
        if n > 0 { parts.append("\(min(n, 60)) request\(n == 1 ? "" : "s")") }
        if l > 0 { parts.append("\(min(l, 60)) log line\(l == 1 ? "" : "s")") }
        parts.append("device details")
        return "Attached: " + parts.joined(separator: " · ")
    }
}
