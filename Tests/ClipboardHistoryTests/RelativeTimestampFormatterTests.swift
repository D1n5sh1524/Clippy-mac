import Testing
import Foundation
@testable import ClipboardHistory

@Suite("RelativeTimestampFormatter Tests")
struct RelativeTimestampFormatterTests {

    let formatter = RelativeTimestampFormatter()
    let now = Date(timeIntervalSince1970: 100000)

    // MARK: - Seconds Unit Tests

    @Test("0 seconds ago")
    func zeroSeconds() {
        let date = now
        #expect(formatter.format(date, relativeTo: now) == "0 seconds ago")
    }

    @Test("1 second ago uses singular")
    func oneSecond() {
        let date = now.addingTimeInterval(-1)
        #expect(formatter.format(date, relativeTo: now) == "1 second ago")
    }

    @Test("59 seconds ago stays in seconds unit")
    func fiftyNineSeconds() {
        let date = now.addingTimeInterval(-59)
        #expect(formatter.format(date, relativeTo: now) == "59 seconds ago")
    }

    @Test("30 seconds ago")
    func thirtySeconds() {
        let date = now.addingTimeInterval(-30)
        #expect(formatter.format(date, relativeTo: now) == "30 seconds ago")
    }

    // MARK: - Minutes Unit Tests

    @Test("60 seconds becomes 1 minute ago")
    func sixtySecondsIsOneMinute() {
        let date = now.addingTimeInterval(-60)
        #expect(formatter.format(date, relativeTo: now) == "1 minute ago")
    }

    @Test("2 minutes ago uses plural")
    func twoMinutes() {
        let date = now.addingTimeInterval(-120)
        #expect(formatter.format(date, relativeTo: now) == "2 minutes ago")
    }

    @Test("59 minutes ago stays in minutes unit")
    func fiftyNineMinutes() {
        let date = now.addingTimeInterval(-3599)
        #expect(formatter.format(date, relativeTo: now) == "59 minutes ago")
    }

    @Test("90 seconds is 1 minute (floor division)")
    func ninetySecondsIsOneMinute() {
        let date = now.addingTimeInterval(-90)
        #expect(formatter.format(date, relativeTo: now) == "1 minute ago")
    }

    // MARK: - Hours Unit Tests

    @Test("3600 seconds becomes 1 hour ago")
    func threeThousandSixHundredIsOneHour() {
        let date = now.addingTimeInterval(-3600)
        #expect(formatter.format(date, relativeTo: now) == "1 hour ago")
    }

    @Test("2 hours ago uses plural")
    func twoHours() {
        let date = now.addingTimeInterval(-7200)
        #expect(formatter.format(date, relativeTo: now) == "2 hours ago")
    }

    @Test("23 hours ago stays in hours unit")
    func twentyThreeHours() {
        let date = now.addingTimeInterval(-86399)
        #expect(formatter.format(date, relativeTo: now) == "23 hours ago")
    }

    @Test("5400 seconds is 1 hour (floor division)")
    func fiveThousandFourHundredIsOneHour() {
        let date = now.addingTimeInterval(-5400)
        #expect(formatter.format(date, relativeTo: now) == "1 hour ago")
    }

    // MARK: - Days Unit Tests

    @Test("86400 seconds becomes 1 day ago")
    func eightySixThousandFourHundredIsOneDay() {
        let date = now.addingTimeInterval(-86400)
        #expect(formatter.format(date, relativeTo: now) == "1 day ago")
    }

    @Test("2 days ago uses plural")
    func twoDays() {
        let date = now.addingTimeInterval(-172800)
        #expect(formatter.format(date, relativeTo: now) == "2 days ago")
    }

    @Test("5 days ago")
    func fiveDays() {
        let date = now.addingTimeInterval(-432000)
        #expect(formatter.format(date, relativeTo: now) == "5 days ago")
    }

    @Test("100000 seconds is 1 day (floor division)")
    func oneHundredThousandSecondsIsOneDay() {
        let date = now.addingTimeInterval(-100000)
        #expect(formatter.format(date, relativeTo: now) == "1 day ago")
    }

    // MARK: - Edge Case Tests

    @Test("Negative interval treated as 0 seconds")
    func futureDate() {
        let date = now.addingTimeInterval(10)
        #expect(formatter.format(date, relativeTo: now) == "0 seconds ago")
    }

    // MARK: - Boundary Tests

    @Test("Boundary at 60 seconds uses minutes")
    func boundaryAtSixty() {
        let date = now.addingTimeInterval(-60)
        #expect(formatter.format(date, relativeTo: now) == "1 minute ago")
    }

    @Test("Boundary at 3600 seconds uses hours")
    func boundaryAtThirtySixHundred() {
        let date = now.addingTimeInterval(-3600)
        #expect(formatter.format(date, relativeTo: now) == "1 hour ago")
    }

    @Test("Boundary at 86400 seconds uses days")
    func boundaryAtEightySixThousandFourHundred() {
        let date = now.addingTimeInterval(-86400)
        #expect(formatter.format(date, relativeTo: now) == "1 day ago")
    }
}
