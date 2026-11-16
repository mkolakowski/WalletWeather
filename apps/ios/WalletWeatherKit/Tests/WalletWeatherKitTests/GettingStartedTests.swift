import Testing
@testable import WalletWeatherKit

/// The Getting started card (#175, #177).
struct GettingStartedTests {
    @Test func aNewPhoneShowsTheCardWithEveryTaskInOrder() {
        let start = GettingStarted()
        #expect(start.showsCard())
        #expect(start.left() == [.tabBar, .lock, .look, .markPaid, .search])
    }

    @Test func goesOnceEveryTaskIsDone() {
        let start = GettingStarted(done: Set(StartTask.allCases))
        #expect(start.left().isEmpty)
        #expect(!start.showsCard())
    }

    @Test func goesWhenDismissedWithTasksLeft() {
        #expect(!GettingStarted(dismissed: true).showsCard())
    }

    /// No Face ID or Touch ID: the lock isn't offered, so it isn't needed
    /// for the card to go.
    @Test func aTaskNotOfferedIsLeftOut() {
        let offered = StartTask.allCases.filter { $0 != .lock }
        let start = GettingStarted(done: [.tabBar, .look, .markPaid, .search])
        #expect(start.left(among: offered).isEmpty)
        #expect(!start.showsCard(among: offered))
        #expect(start.left() == [.lock])
    }

    /// The lock already on, or a look already chosen, counts as done.
    @Test func aTaskDoneBeforeStartsTicked() {
        let start = GettingStarted(done: [.tabBar])
        #expect(start.isDone(.lock, alsoDone: [.lock]))
        #expect(start.left(alsoDone: [.lock, .look]) == [.markPaid, .search])
        #expect(!start.showsCard(alsoDone: [.lock, .look, .markPaid, .search]))
    }

    /// Someone who finished the tab bar task before #177 sees the card again.
    @Test func theCardComesBackWithNewTasks() {
        #expect(GettingStarted(done: [.tabBar]).showsCard())
    }

    @Test func roundTripsAndDropsUnknownTasks() {
        #expect(GettingStarted.done(from: nil).isEmpty)
        #expect(GettingStarted.done(from: "").isEmpty)
        #expect(GettingStarted.done(from: GettingStarted.stored([.search, .tabBar])) == [.tabBar, .search])
        #expect(GettingStarted.stored([.search, .tabBar]) == "tabBar,search")
        #expect(GettingStarted.done(from: "widgets,tabBar,widgets") == [.tabBar])
    }

    @Test func everyTaskHasWords() {
        #expect(StartTask.allCases.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty && !$0.symbol.isEmpty })
    }
}
