import Foundation

/// Thread-safe ring buffer.
final class Ring<T> {
    private var items: [T] = []
    private let cap: Int
    private let lock = NSLock()
    init(cap: Int) { self.cap = cap }
    func push(_ x: T) { lock.lock(); items.append(x); if items.count > cap { items.removeFirst(items.count - cap) }; lock.unlock() }
    func all() -> [T] { lock.lock(); defer { lock.unlock() }; return items }
}

struct LogLine { let level: String; let message: String; let at: Double }
struct NetCall { let method: String; let url: String; let status: Int; let durationMs: Int; let at: Double }

func nowMs() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

/// Mirrors stdout and stderr into a ring buffer while still writing to the console.
final class LogCapture {
    static let shared = LogCapture()
    let lines = Ring<LogLine>(cap: 200)
    private var started = false
    private var pending: [Int32: String] = [:]
    private var pipes: [Pipe] = [] // kept alive for the life of the app; a freed pipe would kill the next print with SIGPIPE
    private let queue = DispatchQueue(label: "dev.astratest.logs")

    func append(level: String, message: String) {
        let m = String(message.prefix(2000))
        lines.push(LogLine(level: level, message: m, at: nowMs()))
    }

    func start() {
        guard !started else { return }
        started = true
        setvbuf(stdout, nil, _IOLBF, 0)
        for (fd, level) in [(STDOUT_FILENO, "log"), (STDERR_FILENO, "error")] { mirror(fd: fd, level: level) }
    }

    private func mirror(fd: Int32, level: String) {
        let original = dup(fd)
        guard original >= 0 else { return }
        let pipe = Pipe()
        pipes.append(pipe)
        dup2(pipe.fileHandleForWriting.fileDescriptor, fd)
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let self else { return }
            data.withUnsafeBytes { _ = write(original, $0.baseAddress, data.count) }
            guard let text = String(data: data, encoding: .utf8) else { return }
            self.queue.async {
                var buf = (self.pending[fd] ?? "") + text
                while let r = buf.range(of: "\n") {
                    let line = String(buf[buf.startIndex..<r.lowerBound])
                    buf = String(buf[r.upperBound...])
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty && !t.hasPrefix("[AstraTest]") {
                        let lower = t.lowercased()
                        let lv = lower.contains("error") || lower.contains("fatal") ? "error" : lower.contains("warn") ? "warn" : (level == "error" ? "log" : level)
                        self.append(level: lv, message: t)
                    }
                }
                self.pending[fd] = String(buf.suffix(4000))
            }
        }
    }
}

/// Records URLSession traffic through a URLProtocol that forwards every request unchanged.
final class NetworkCapture: URLProtocol {
    static let calls = Ring<NetCall>(cap: 100)
    private static let handledKey = "dev.astratest.handled"
    private static var installed = false
    private static let forward: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = (c.protocolClasses ?? []).filter { $0 != NetworkCapture.self }
        return URLSession(configuration: c)
    }()
    private var forwardTask: URLSessionDataTask?
    private var startedAt = Date()

    static func install() {
        guard !installed else { return }
        installed = true
        URLProtocol.registerClass(NetworkCapture.self)
        swizzleDefaultConfigurations()
    }

    static func instrument(_ c: URLSessionConfiguration) {
        var p = c.protocolClasses ?? []
        if !p.contains(where: { $0 == NetworkCapture.self }) { p.insert(NetworkCapture.self, at: 0) }
        c.protocolClasses = p
    }

    /// Sessions built from `.default` / `.ephemeral` (Alamofire and most clients) get the protocol too.
    private static func swizzleDefaultConfigurations() {
        let cls: AnyClass = object_getClass(URLSessionConfiguration.self)!
        for (orig, repl) in [(#selector(getter: URLSessionConfiguration.default), #selector(getter: URLSessionConfiguration.astra_default)),
                             (#selector(getter: URLSessionConfiguration.ephemeral), #selector(getter: URLSessionConfiguration.astra_ephemeral))] {
            if let a = class_getClassMethod(cls, orig), let b = class_getClassMethod(cls, repl) { method_exchangeImplementations(a, b) }
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        if URLProtocol.property(forKey: handledKey, in: request) != nil { return false }
        // Don't record Astra Test's own calls.
        if let host = request.url?.host, host == AstraTest.options.host.host { return false }
        return true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let m = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else { return }
        URLProtocol.setProperty(true, forKey: NetworkCapture.handledKey, in: m)
        startedAt = Date()
        forwardTask = NetworkCapture.forward.dataTask(with: m as URLRequest) { [weak self] data, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            NetworkCapture.record(self.request, status: status, since: self.startedAt)
            if let error { self.client?.urlProtocol(self, didFailWithError: error); return }
            if let response { self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
            if let data { self.client?.urlProtocol(self, didLoad: data) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        forwardTask?.resume()
    }
    override func stopLoading() { forwardTask?.cancel() }

    static func record(_ r: URLRequest, status: Int, since: Date) {
        guard let u = r.url else { return }
        var c = URLComponents(url: u, resolvingAgainstBaseURL: false)
        c?.query = nil; c?.fragment = nil
        calls.push(NetCall(method: r.httpMethod ?? "GET", url: String((c?.string ?? u.absoluteString).prefix(500)), status: status,
                           durationMs: Int(Date().timeIntervalSince(since) * 1000), at: nowMs()))
    }
}

extension URLSessionConfiguration {
    @objc class var astra_default: URLSessionConfiguration {
        let c = self.astra_default // the original, after the swap
        NetworkCapture.instrument(c)
        return c
    }
    @objc class var astra_ephemeral: URLSessionConfiguration {
        let c = self.astra_ephemeral
        NetworkCapture.instrument(c)
        return c
    }
}
