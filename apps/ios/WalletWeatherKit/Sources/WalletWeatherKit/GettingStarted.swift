/// The Getting started card on the Dashboard (#175): a short list of things
/// worth doing once, each ticked when it's done. The card goes for good once
/// every task is done or it's dismissed. It's kept per phone, so signing in
/// again shows it only if it was never finished or dismissed, and someone
/// already signed in sees it once after updating. Four tasks joined the tab
/// bar in #177; a phone may not offer every task (no lock without Face ID or
/// Touch ID), and a task done before the card knew of it starts ticked.
public enum StartTask: String, CaseIterable, Identifiable, Sendable {
    case tabBar, lock, look, markPaid, search

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tabBar: "Make the tab bar yours"
        case .lock: "Lock the app"
        case .look: "Choose a look"
        case .markPaid: "Mark a bill paid"
        case .search: "Try Search"
        }
    }

    public var detail: String {
        switch self {
        case .tabBar: "Swap Calendar, Net worth, Budgets or Reports into the tab bar."
        case .lock: "Ask for Face ID or Touch ID when WalletWeather opens."
        case .look: "Light, Dark, Sepia, or one of the web app's themes."
        case .markPaid: "Confirm a line once it's gone through, from Forecast's To confirm list."
        case .search: "Find transactions, bills, accounts, categories, tags and reports."
        }
    }

    public var symbol: String {
        switch self {
        case .tabBar: "dock.rectangle"
        case .lock: "faceid"
        case .look: "paintpalette"
        case .markPaid: "checklist"
        case .search: "magnifyingglass"
        }
    }
}

public struct GettingStarted: Equatable, Sendable {
    public var done: Set<StartTask>
    public var dismissed: Bool

    public init(done: Set<StartTask> = [], dismissed: Bool = false) {
        self.done = done
        self.dismissed = dismissed
    }

    /// Whether a task is done: ticked here, or found done another way
    /// (`alsoDone`, such as the lock already on).
    public func isDone(_ task: StartTask, alsoDone: Set<StartTask> = []) -> Bool {
        done.contains(task) || alsoDone.contains(task)
    }

    /// The tasks not done yet among those this phone offers, in the card's
    /// order.
    public func left(among tasks: [StartTask] = StartTask.allCases, alsoDone: Set<StartTask> = []) -> [StartTask] {
        tasks.filter { !isDone($0, alsoDone: alsoDone) }
    }

    /// The card shows until it's dismissed or every task offered is done.
    public func showsCard(among tasks: [StartTask] = StartTask.allCases, alsoDone: Set<StartTask> = []) -> Bool {
        !dismissed && !left(among: tasks, alsoDone: alsoDone).isEmpty
    }

    /// The done tasks from their stored form (raw values joined by commas);
    /// tasks this version doesn't know are dropped.
    public static func done(from stored: String?) -> Set<StartTask> {
        Set((stored ?? "").split(separator: ",").compactMap { StartTask(rawValue: String($0)) })
    }

    /// Stored in the card's order, so the same set always reads the same.
    public static func stored(_ done: Set<StartTask>) -> String {
        StartTask.allCases.filter(done.contains).map(\.rawValue).joined(separator: ",")
    }
}
