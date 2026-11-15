import Charts
import SwiftUI
import WalletWeatherKit

/// One account's charts for the chosen window: the balance over the days,
/// income and spending (actual against forecast), and spending by category,
/// as the web Dashboard's chart block shows them.
struct AccountChartsCard: View {
    let account: DashboardCharts.AccountCharts

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(account.accountName).font(.headline)
            BalanceChart(points: account.balanceTrend)
            TotalsGrid(totals: account.totals)
            CategoryDonut(categories: account.topCategories, total: account.totalSpending)
        }
        .card()
    }
}

struct BalanceChart: View {
    let points: [DashboardCharts.BalancePoint]

    var body: some View {
        let low = points.map(\.balance).min() ?? .zero
        Chart(points) { point in
            AreaMark(x: .value("Day", point.date.date), y: .value("Balance", point.balance.amount))
                .foregroundStyle(LinearGradient(colors: [Palette.accent.opacity(0.35), Palette.accent.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Day", point.date.date), y: .value("Balance", point.balance.amount))
                .foregroundStyle(Palette.accent)
                .lineStyle(StrokeStyle(lineWidth: 2))
            if low.isNegative {
                RuleMark(y: .value("Zero", 0)).foregroundStyle(Palette.bad.opacity(0.6))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel { if let v = value.as(Double.self) { Text(Money(v).short) } }
            }
        }
        .frame(height: 150)
        .accessibilityLabel("Balance over the window")
        .accessibilityValue(points.last.map { "Ends at \($0.balance.formatted)" } ?? "No data")
    }
}

struct TotalsGrid: View {
    let totals: DashboardCharts.Totals

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("")
                Text("Actual").font(.caption).foregroundStyle(.secondary)
                Text("Forecast").font(.caption).foregroundStyle(.secondary)
            }
            row("Income", totals.incomeActual, totals.incomeForecast, color: Palette.good)
            row("Spending", totals.spendingActual, totals.spendingForecast, color: Palette.bad)
            row("Net", totals.netActual, totals.netForecast, color: nil)
        }
        .font(.callout)
    }

    private func row(_ label: String, _ actual: Money, _ forecast: Money, color: Color?) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(actual.formatted).monospacedDigit()
                .foregroundStyle(color ?? Palette.amount(actual.isNegative))
            Text(forecast.formatted).monospacedDigit()
                .foregroundStyle(color ?? Palette.amount(forecast.isNegative))
        }
    }
}

struct CategoryDonut: View {
    let categories: [DashboardCharts.CategorySpend]
    let total: Money

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Caption("Expenses by category")
            if categories.isEmpty {
                Text("No expenses in this window.").font(.callout).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Chart(categories) { c in
                        SectorMark(angle: .value("Spent", c.spendingActual.amount), innerRadius: .ratio(0.6), angularInset: 1)
                            .foregroundStyle(Palette.category(c.color, name: c.name))
                    }
                    .chartBackground { _ in
                        VStack(spacing: 0) {
                            Text(total.short).font(.headline.monospacedDigit())
                            Text("spent").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 120, height: 120)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(categories) { c in
                            HStack(spacing: 6) {
                                Circle().fill(Palette.category(c.color, name: c.name)).frame(width: 9, height: 9)
                                Text(c.name).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(c.spendingActual.formatted).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }
}

/// A pinned saved report: its range, actual net, items, and its five
/// biggest groups as bars.
struct PinnedReportCard: View {
    let report: SavedReport
    let run: Loadable<ReportRun>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "pin.fill").foregroundStyle(Palette.accent).accessibilityHidden(true)
                Text(report.name).font(.headline)
            }
            switch run {
            case .loading:
                ProgressView()
            case let .failed(error):
                Text("Couldn't run it. \(error.message)").font(.callout).foregroundStyle(Palette.bad)
            case let .loaded(result):
                HStack(spacing: 14) {
                    Text(result.rangeLabel)
                    Text("Net \(result.totals.actualNet.formatted)").monospacedDigit()
                    Text("\(result.itemCount) items")
                }
                .font(.caption).foregroundStyle(.secondary)
                if result.topGroups.isEmpty {
                    Text("No data.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Chart(result.topGroups) { g in
                        BarMark(x: .value("Total", abs(g.actualTotal.amount)), y: .value("Group", g.name))
                            .foregroundStyle(Palette.category(g.color, name: g.name))
                            .annotation(position: .trailing) {
                                Text(Money(abs(g.actualTotal.amount)).short).font(.caption2).foregroundStyle(.secondary)
                            }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(result.topGroups.count) * 30 + 10)
                }
            }
        }
        .card()
    }
}
