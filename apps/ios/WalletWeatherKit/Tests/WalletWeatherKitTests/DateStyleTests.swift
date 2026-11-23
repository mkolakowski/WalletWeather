import Foundation
import Testing
@testable import WalletWeatherKit

/// The date format (ios-settings phase 3, #296, finding R18): one helper
/// writes every date the app shows, as the web app does.
struct DateStyleTests {
    let today = LocalDay(year: 2026, month: 11, day: 23)
    let us = Locale(identifier: "en_US")

    @Test func shortLeavesOutTheCurrentYear() {
        #expect(LocalDay(year: 2026, month: 11, day: 12).display(.short, today: today, locale: us) == "Nov 12")
        #expect(LocalDay(year: 2026, month: 1, day: 3).display(.short, today: today, locale: us) == "Jan 3")
    }

    @Test func shortAddsTheYearOutsideTheCurrentOne() {
        #expect(LocalDay(year: 2025, month: 11, day: 12).display(.short, today: today, locale: us) == "Nov 12, 2025")
        #expect(LocalDay(year: 2027, month: 1, day: 5).display(.short, today: today, locale: us) == "Jan 5, 2027")
    }

    @Test func isoIsAlwaysTheFullDate() {
        #expect(LocalDay(year: 2026, month: 11, day: 12).display(.iso, today: today) == "2026-11-12")
        #expect(LocalDay(year: 2025, month: 1, day: 3).display(.iso, today: today) == "2025-01-03")
    }

    @Test func requestsAndStorageKeepTheirFormat() {
        #expect(LocalDay(year: 2025, month: 1, day: 3).description == "2025-01-03")
    }

    @Test func serverValueReadsShortUnlessIso() {
        #expect(DateStyle(server: "iso") == .iso)
        #expect(DateStyle(server: "short") == .short)
        #expect(DateStyle(server: nil) == .short)
        #expect(DateStyle(server: "something-new") == .short)
    }

    @Test func whichChoiceWins() {
        #expect(DateFormatChoice.follow.style(server: "iso") == .iso)
        #expect(DateFormatChoice.follow.style(server: "short") == .short)
        #expect(DateFormatChoice.follow.style(server: nil) == .short)
        // An explicit choice beats the server's.
        #expect(DateFormatChoice.short.style(server: "iso") == .short)
        #expect(DateFormatChoice.iso.style(server: "short") == .iso)
        #expect(DateFormatChoice.iso.style(server: nil) == .iso)
    }

    @Test func followIsOfferedOnlyWithAServer() {
        #expect(DateFormatChoice.offered(hasServer: true) == [.follow, .short, .iso])
        #expect(DateFormatChoice.offered(hasServer: false) == [.short, .iso])
    }

    @Test func storedValuesKeepTheirNames() {
        #expect(DateFormatChoice.allCases.map(\.rawValue) == ["follow", "short", "iso"])
        #expect(DateFormatChoice.allCases.map(\.title) == ["Follow the web app", "Nov 12", "2026-11-12"])
    }

    @Test func meReadsDateFormatAndManagesWithout() throws {
        let with = Data(#"{"id":1,"email":"a@b.c","name":null,"is_admin":false,"notice_required":false,"date_format":"iso"}"#.utf8)
        #expect(try APIClient.decoder().decode(Me.self, from: with).dateFormat == "iso")
        let null = Data(#"{"id":1,"email":"a@b.c","name":null,"is_admin":false,"notice_required":false,"date_format":null}"#.utf8)
        #expect(try APIClient.decoder().decode(Me.self, from: null).dateFormat == nil)
        // An older server, the demo's sample and the household on the phone send no such key.
        let without = Data(#"{"id":1,"email":"a@b.c","name":null,"is_admin":false,"notice_required":false}"#.utf8)
        #expect(try APIClient.decoder().decode(Me.self, from: without).dateFormat == nil)
        let sample: Me = try DecodingTests().sample("me")
        #expect(sample.dateFormat == nil)
    }
}

/// Changes the app-wide style, so it runs alone and puts it back.
@Suite(.serialized) struct DateDisplayTests {
    @Test func shortFollowsTheStyleTheAppSets() {
        let day = LocalDay.today()
        let before = DateDisplay.style
        defer { DateDisplay.style = before }
        DateDisplay.style = .iso
        #expect(day.short == day.description)
        DateDisplay.style = .short
        #expect(day.short == day.display(.short))
    }
}
