import Testing
@testable import WalletWeatherKit

/// The Getting started card (#175).
struct GettingStartedTests {
    @Test func aNewPhoneShowsTheCardWithEveryTask() {
        let start = GettingStarted()
        #expect(start.showsCard)
        #expect(start.left == StartTask.allCases)
        #expect(start.left.first == .tabBar)
    }

    @Test func goesOnceEveryTaskIsDone() {
        let start = GettingStarted(done: Set(StartTask.allCases))
        #expect(start.left.isEmpty)
        #expect(!start.showsCard)
    }

    @Test func goesWhenDismissedWithTasksLeft() {
        #expect(!GettingStarted(dismissed: true).showsCard)
    }

    @Test func roundTripsAndDropsUnknownTasks() {
        #expect(GettingStarted.done(from: nil).isEmpty)
        #expect(GettingStarted.done(from: "").isEmpty)
        #expect(GettingStarted.done(from: GettingStarted.stored([.tabBar])) == [.tabBar])
        #expect(GettingStarted.done(from: "lock,tabBar,lock") == [.tabBar])
    }

    @Test func everyTaskHasWords() {
        #expect(StartTask.allCases.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty && !$0.symbol.isEmpty })
    }
}
