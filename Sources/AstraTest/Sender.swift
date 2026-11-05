import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// What the user pointed at: a description of the view, its text, and where it was on the screen.
struct PickedElement { let selector: String; let text: String?; let frame: CGRect }

enum Device {
    static var platform: String {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios"
        #else
        return "macos"
        #endif
    }
    static var model: String {
        var s = utsname(); uname(&s)
        let id = withUnsafeBytes(of: &s.machine) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        #if targetEnvironment(simulator)
        return "Simulator (\(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? id))"
        #else
        return id
        #endif
    }
    static var os: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
        let name = platform == "ipados" ? "iPadOS" : "iOS"
        #else
        let name = "macOS"
        #endif
        return "\(name) \(v.majorVersion).\(v.minorVersion)\(v.patchVersion > 0 ? ".\(v.patchVersion)" : "")"
    }
    static var screen: String {
        #if os(iOS)
        let b = UIScreen.main.bounds
        return "\(Int(b.width)) × \(Int(b.height)) pt"
        #else
        if let f = NSApplication.shared.keyWindow?.frame ?? NSApplication.shared.windows.first?.frame { return "\(Int(f.width)) × \(Int(f.height)) pt window" }
        return ""
        #endif
    }
    static var appVersion: String? { AstraTest.options.appVersion ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }
    static var build: String? { AstraTest.options.build ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String }
    static var appName: String { (Bundle.main.infoDictionary?["CFBundleDisplayName"] ?? Bundle.main.infoDictionary?["CFBundleName"]) as? String ?? "App" }
}

enum Sender {
    struct ApiError: LocalizedError { let message: String; var errorDescription: String? { message } }

    static func announceBuild() {
        guard let key = AstraTest.key, let version = Device.appVersion else { return }
        post("/v1/builds", ["key": key, "platform": Device.platform, "version": version, "build": Device.build ?? "",
                            "sdk": "apple", "sdkVersion": AstraTest.version]) { result in
            guard case .success(let json) = result, let latest = json["latest"] as? [String: Any],
                  let v = latest["version"] as? String, isOlder(AstraTest.version, than: v) else { return }
            let urgent = (latest["urgent"] as? Bool) == true
            print("[AstraTest] \(urgent ? "Important update" : "Update available"): AstraTest \(v) (this app has \(AstraTest.version)). \(latest["notes"] as? String ?? "") \(latest["upgrade"] as? String ?? "")")
        }
    }

    static func isOlder(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q }
        }
        return false
    }

    static func payload(description: String, severity: String?, element: PickedElement?, screenshot: Data?) -> [String: Any] {
        var page: [String: Any] = ["url": "app://\(Device.appName)/\(AstraTest.screenName ?? Presenter.currentScreen() ?? "")", "title": AstraTest.screenName ?? Presenter.currentScreen() ?? Device.appName]
        if let e = element { page["selector"] = e.selector; if let t = e.text { page["selectorText"] = String(t.prefix(120)) } }
        var device: [String: Any] = ["platform": Device.platform, "os": Device.os, "browser": Device.model, "viewport": Device.screen, "locale": Locale.preferredLanguages.first ?? Locale.current.identifier]
        if let v = Device.appVersion { device["appVersion"] = v }
        if let b = Device.build { device["build"] = b }
        var body: [String: Any] = [
            "key": AstraTest.key ?? "",
            "description": description,
            "page": page,
            "device": device,
            "console": LogCapture.shared.lines.all().suffix(60).map { ["level": $0.level, "message": $0.message, "at": $0.at] },
            "network": NetworkCapture.calls.all().suffix(60).map { ["method": $0.method, "url": $0.url, "status": $0.status, "durationMs": $0.durationMs, "at": $0.at] },
        ]
        if let severity { body["severity"] = severity }
        if !AstraTest.reporter.isEmpty { body["reporter"] = AstraTest.reporter }
        if let t = AstraTest.testCase { body["testCaseRef"] = t }
        if let s = screenshot { body["screenshot"] = "data:image/jpeg;base64," + s.base64EncodedString() }
        return body
    }

    static func send(description: String, severity: String?, element: PickedElement?, screenshot: Data?, completion: @escaping (Result<AstraTest.SentReport, Error>) -> Void) {
        DispatchQueue.main.async {
            let body = payload(description: description, severity: severity, element: element, screenshot: screenshot)
            post("/v1/reports", body) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let e): completion(.failure(e))
                    case .success(let json):
                        if let ref = json["ref"] as? String {
                            completion(.success(.init(ref: ref, url: (json["url"] as? String).flatMap(URL.init(string:)), title: json["title"] as? String)))
                        } else {
                            completion(.failure(ApiError(message: json["error"] as? String ?? "Couldn't send the report")))
                        }
                    }
                }
            }
        }
    }

    static func post(_ path: String, _ body: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard AstraTest.key != nil, let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var r = URLRequest(url: AstraTest.options.host.appendingPathComponent(path))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = data
        r.timeoutInterval = 60
        URLSession(configuration: .ephemeral).dataTask(with: r) { d, resp, err in
            if let err { return completion(.failure(err)) }
            let json = (d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) { completion(.success(json)) }
            else { completion(.failure(ApiError(message: json["error"] as? String ?? "Couldn't send the report (\(code))"))) }
        }.resume()
    }
}
