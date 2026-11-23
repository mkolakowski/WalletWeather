import SwiftUI
import WalletWeatherKit

/// A page's data: loading, loaded, or why it couldn't be.
enum Loadable<Value> {
    case loading
    case loaded(Value)
    case failed(APIError)

    var value: Value? {
        if case let .loaded(v) = self { return v }
        return nil
    }
}

/// Why a page couldn't load, in plain words, with the way forward: Try
/// again, Sign in to Cloudflare, or Sign in again.
struct ProblemView: View {
    @Environment(AppModel.self) private var model
    let error: APIError
    let retry: () -> Void
    /// Sign in again: the sign-in screen as a sheet, for this server only;
    /// the other connections stay as they are (#300).
    @State private var signingIn = false

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: symbol)
        } description: {
            Text(error.message)
        } actions: {
            // A page that couldn't load always offers at least Try again.
            WayForwardButton(way: error.wayForward ?? .tryAgain, signingIn: $signingIn, retry: retry)
                .buttonStyle(.glassProminent)
        }
        .sheet(isPresented: $signingIn) { AddServerSheet(server: model.connection?.server) }
    }

    private var symbol: String {
        switch error {
        case .offline: "wifi.slash"
        case .slowServer: "hourglass"
        case .cloudflareSignInNeeded, .tokenExpired, .tokenRevoked: "person.badge.key"
        case .serverTooOld: "arrow.up.circle"
        default: "exclamationmark.triangle"
        }
    }
}

// MARK: - Last-known numbers (#101)

/// Where a page's numbers came from: `keptAt` is set while it shows the
/// phone's kept copy because the server can't be reached, and cleared as
/// soon as the server answers again. With several kept answers on a page,
/// it holds the oldest.
@MainActor @Observable
final class KeptTracker {
    private(set) var keptAt: Date?

    /// The page couldn't load at all: it shows why, not kept numbers.
    func clear() { keptAt = nil }

    func record(_ date: Date?) {
        guard let date else {
            keptAt = nil
            return
        }
        keptAt = min(keptAt ?? date, date)
    }
}

/// The bar over a page showing kept numbers: how old they are, and that
/// changes wait for a connection.
struct KeptBar: View {
    let keptAt: Date

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text("Offline · as loaded \(Self.when(keptAt))").font(.subheadline.weight(.semibold))
                Text("Your server can't be reached, so changes wait until it can.").font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    /// "today at 3:12 PM", "yesterday at 9:05 AM", "Nov 12 at 6:40 PM".
    static func when(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "today at \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday at \(time)"
        }
        return "\(LocalDay.display(of: date, now: now)) at \(time)"
    }
}

/// The bar over every page in the demo (#92): that the numbers are
/// samples, and the way back to the Connect screen.
struct DemoBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Demo · sample numbers").font(.subheadline.weight(.semibold))
                    Text("Nothing you change here is saved.").font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "sparkles")
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button("Leave") { model.leaveDemo() }
                .buttonStyle(.glass)
                .accessibilityHint("Goes back to the Connect screen")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

extension View {
    /// The kept-numbers bar at the top of a page, while it shows them.
    func keptBar(_ tracker: KeptTracker) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if let keptAt = tracker.keptAt {
                KeptBar(keptAt: keptAt).padding(.horizontal, 16).padding(.bottom, 6)
            }
        }
    }
}
