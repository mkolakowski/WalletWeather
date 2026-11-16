/// The Getting started card on the Dashboard (#175): a short list of things
/// worth doing once, each ticked when it's done. The card goes for good once
/// every task is done or it's dismissed. It's kept per phone, so signing in
/// again shows it only if it was never finished or dismissed, and someone
/// already signed in sees it once after updating.
public enum StartTask: String, CaseIterable, Identifiable, Sendable {
    case tabBar

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tabBar: "Make the tab bar yours"
        }
    }

    public var detail: String {
        switch self {
        case .tabBar: "Swap Calendar, Net worth, Budgets or Reports into the bar at the bottom."
        }
    }

    public var symbol: String {
        switch self {
        case .tabBar: "dock.rectangle"
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

    /// The tasks not done yet, in the card's order.
    public var left: [StartTask] { StartTask.allCases.filter { !done.contains($0) } }

    /// The card shows until it's dismissed or every task is done.
    public var showsCard: Bool { !dismissed && !left.isEmpty }

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
