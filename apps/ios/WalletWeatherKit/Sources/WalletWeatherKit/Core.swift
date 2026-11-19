import Foundation
import JavaScriptCore

/// The shared JavaScript core (`packages/core/walletweather-core.js`): the
/// money logic the server runs, run here in JavaScriptCore so the app can
/// work its numbers out without a server (Plans/standalone.md, phase 3,
/// #234). JavaScriptCore is part of iOS, so nothing is added to
/// THIRD_PARTY_NOTICES.md.
///
/// `Core/walletweather-core.js` in this package is a copy (SwiftPM can't
/// take a resource from outside the package); `Scripts/copy-core.sh`
/// refreshes it and `CoreTests` fails when it differs from the original.
///
/// One context for the app, used by one caller at a time: JavaScriptCore
/// contexts aren't safe to share between threads unguarded.
public final class Core: @unchecked Sendable {
    public static let shared = Core()

    public enum Problem: Error, Equatable, Sendable {
        /// The core file isn't in the bundle.
        case missing
        /// The core threw, or its answer wasn't JSON.
        case failed(String)
    }

    private let lock = NSLock()
    private var context: JSContext?
    private var thrown: String?

    init() {}

    /// The core's source, from this package's bundle.
    static func source() -> String? {
        guard let url = Bundle.module.url(forResource: "walletweather-core", withExtension: "js", subdirectory: "Core"),
              let data = try? Data(contentsOf: url) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Calls one of the core's functions with a JSON input and returns its
    /// JSON answer, in the same shape the server sends.
    public func run(_ name: String, json: Data) throws(Problem) -> Data {
        let text = try evaluate { context in
            context.objectForKeyedSubscript("WalletWeatherCore")?
                .objectForKeyedSubscript("run")?
                .call(withArguments: [name, String(decoding: json, as: UTF8.self)])
        }
        return Data(text.utf8)
    }

    /// The same with plain JSON values (dictionaries, arrays, strings,
    /// numbers, booleans and NSNull) in and out.
    public func run(_ name: String, _ input: Any) throws(Problem) -> Any {
        guard let data = try? JSONSerialization.data(withJSONObject: input) else {
            throw .failed("the input isn't JSON")
        }
        let answer = try run(name, json: data)
        guard let value = try? JSONSerialization.jsonObject(with: answer, options: [.fragmentsAllowed]) else {
            throw .failed("the answer isn't JSON")
        }
        return value
    }

    /// Runs a script against the loaded core and returns its result as a
    /// string. For the tests: the answer key is compared inside JavaScript,
    /// where numbers stay exact.
    func evaluate(_ script: String) throws(Problem) -> String {
        try evaluate { $0.evaluateScript(script) }
    }

    private func evaluate(_ body: (JSContext) -> JSValue?) throws(Problem) -> String {
        lock.lock()
        defer { lock.unlock() }
        let context = try loaded()
        thrown = nil
        let value = body(context)
        if let thrown { throw .failed(thrown) }
        guard let value, !value.isUndefined, let text = value.toString() else {
            throw .failed("the core gave no answer")
        }
        return text
    }

    private func loaded() throws(Problem) -> JSContext {
        if let context { return context }
        guard let source = Self.source(), let context = JSContext() else { throw .missing }
        context.name = "WalletWeather core"
        context.exceptionHandler = { [weak self] _, exception in
            self?.thrown = exception?.toString() ?? "the core threw"
        }
        context.evaluateScript(source, withSourceURL: URL(string: "walletweather-core.js"))
        if let thrown { throw .failed(thrown) }
        self.context = context
        return context
    }
}
