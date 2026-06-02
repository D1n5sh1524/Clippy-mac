import Testing
import Foundation
import SwiftCheck
@testable import ClipboardHistory

// Feature: mac-clipboard-history, Property 11: Relative timestamp formatting uses largest applicable unit

/// **Validates: Requirements 4.4**
///
/// Property: For any time interval between 0 seconds and an arbitrary upper bound,
/// the relative timestamp formatter SHALL express the interval using the largest
/// applicable unit:
/// - days if ≥ 86400s (with count = interval / 86400)
/// - hours if ≥ 3600s (with count = interval / 3600)
/// - minutes if ≥ 60s (with count = interval / 60)
/// - seconds otherwise (with count = interval)

// MARK: - Generators

/// Generator for time intervals (in seconds) from 0 to 1,000,000 (~11.5 days)
/// with emphasis on boundary values near unit thresholds.
private let timeIntervalGen: Gen<Int> = Gen<Int>.frequency([
    // 20% near seconds/minutes boundary (50-70)
    (2, Gen<Int>.fromElements(in: 50...70)),
    // 20% near minutes/hours boundary (3590-3610)
    (2, Gen<Int>.fromElements(in: 3590...3610)),
    // 20% near hours/days boundary (86390-86410)
    (2, Gen<Int>.fromElements(in: 86390...86410)),
    // 20% general seconds range (0-59)
    (2, Gen<Int>.fromElements(in: 0...59)),
    // 10% general minutes range (60-3599)
    (1, Gen<Int>.fromElements(in: 60...3599)),
    // 5% general hours range (3600-86399)
    (1, Gen<Int>.fromElements(in: 3600...86399)),
    // 5% general days range (86400-1000000)
    (1, Gen<Int>.fromElements(in: 86400...1000000))
])

/// Generator for intervals specifically in the seconds range (0-59).
private let secondsRangeGen: Gen<Int> = Gen<Int>.fromElements(in: 0...59)

/// Generator for intervals specifically in the minutes range (60-3599).
private let minutesRangeGen: Gen<Int> = Gen<Int>.fromElements(in: 60...3599)

/// Generator for intervals specifically in the hours range (3600-86399).
private let hoursRangeGen: Gen<Int> = Gen<Int>.fromElements(in: 3600...86399)

/// Generator for intervals specifically in the days range (86400-1000000).
private let daysRangeGen: Gen<Int> = Gen<Int>.fromElements(in: 86400...1000000)

// MARK: - Property Tests

@Suite("Relative Timestamp Formatter Property Tests")
struct RelativeTimestampFormatterPropertyTests {

    let formatter = RelativeTimestampFormatter()
    let referenceDate = Date(timeIntervalSince1970: 1000000)

    // MARK: - Property 11a: Correct unit selection based on thresholds

    @Test("Intervals < 60s use seconds unit")
    func intervalsUnderSixtyUseSeconds() {
        property("For any interval in [0, 59], output contains 'second' or 'seconds'")
            <- forAll(secondsRangeGen) { interval in
                let date = self.referenceDate.addingTimeInterval(-Double(interval))
                let result = self.formatter.format(date, relativeTo: self.referenceDate)
                let usesSeconds = result.contains("second")
                return usesSeconds
                    <?> "Interval \(interval)s produced '\(result)' which doesn't use seconds unit"
            }
    }

    @Test("Intervals in [60, 3599] use minutes unit")
    func intervalsInMinutesRangeUseMinutes() {
        property("For any interval in [60, 3599], output contains 'minute' or 'minutes'")
            <- forAll(minutesRangeGen) { interval in
                let date = self.referenceDate.addingTimeInterval(-Double(interval))
                let result = self.formatter.format(date, relativeTo: self.referenceDate)
                let usesMinutes = result.contains("minute")
                return usesMinutes
                    <?> "Interval \(interval)s produced '\(result)' which doesn't use minutes unit"
            }
    }

    @Test("Intervals in [3600, 86399] use hours unit")
    func intervalsInHoursRangeUseHours() {
        property("For any interval in [3600, 86399], output contains 'hour' or 'hours'")
            <- forAll(hoursRangeGen) { interval in
                let date = self.referenceDate.addingTimeInterval(-Double(interval))
                let result = self.formatter.format(date, relativeTo: self.referenceDate)
                let usesHours = result.contains("hour")
                return usesHours
                    <?> "Interval \(interval)s produced '\(result)' which doesn't use hours unit"
            }
    }

    @Test("Intervals >= 86400 use days unit")
    func intervalsInDaysRangeUseDays() {
        property("For any interval in [86400, 1000000], output contains 'day' or 'days'")
            <- forAll(daysRangeGen) { interval in
                let date = self.referenceDate.addingTimeInterval(-Double(interval))
                let result = self.formatter.format(date, relativeTo: self.referenceDate)
                let usesDays = result.contains("day")
                return usesDays
                    <?> "Interval \(interval)s produced '\(result)' which doesn't use days unit"
            }
    }

    // MARK: - Property 11b: Correct count for each unit

    @Test("Seconds count equals the interval value")
    func secondsCountIsCorrect() {
        property("For intervals [0, 59], count equals the interval itself")
            <- forAll(secondsRangeGen) { interval in
                let date = self.referenceDate.addingTimeInterval(-Double(interval))
                let result = self.formatter.format(date, relativeTo: self.referenceDate)
                let expectedCount = interval
                let expectedString: String
                if expectedCount == 1 {
                    expectedString = "1 second ago"
                } else {
                    expectedString = "\(expectedCount) seconds ago"
                }
                return (result == expectedString)
                    <?> "Interval \(interval)s: expected '\(expectedString)' but got '\(result)'"
            }
    }

    @Test("Minutes count equals interval / 60 (floor division)")
    func minutesCountIsCorrect() {
        property("For intervals [60, 3599], count equals interval / 60")
            <- forAll(minutesRangeGen) { interval in
                let date = self.referenceDate.addingTimeInterval(-Double(interval))
                let result = self.formatter.format(date, relativeTo: self.referenceDate)
                let expectedCount = interval / 60
                let expectedString: String
                if expectedCount == 1 {
                    expectedString = "1 minute ago"
                } else {
                    expectedString = "\(expectedCount) minutes ago"
                }
                return (result == expectedString)
                    <?> "Interval \(interval)s: expected '\(expectedString)' but got '\(result)'"
            }
    }

    @Test("Hours count equals interval / 3600 (floor division)")
    func hoursCountIsCorrect() {
        property("For intervals [3600, 86399], count equals interval / 3600")
            <- forAll(hoursRangeGen) { interval in
                let date = self.referenceDate.addingTimeInterval(-Double(interval))
                let result = self.formatter.format(date, relativeTo: self.referenceDate)
                let expectedCount = interval / 3600
                let expectedString: String
                if expectedCount == 1 {
                    expectedString = "1 hour ago"
                } else {
                    expectedString = "\(expectedCount) hours ago"
                }
                return (result == expectedString)
                    <?> "Interval \(interval)s: expected '\(expectedString)' but got '\(result)'"
            }
    }

    @Test("Days count equals interval / 86400 (floor division)")
    func daysCountIsCorrect() {
        property("For intervals [86400, 1000000], count equals interval / 86400")
            <- forAll(daysRangeGen) { interval in
                let date = self.referenceDate.addingTimeInterval(-Double(interval))
                let result = self.formatter.format(date, relativeTo: self.referenceDate)
                let expectedCount = interval / 86400
                let expectedString: String
                if expectedCount == 1 {
                    expectedString = "1 day ago"
                } else {
                    expectedString = "\(expectedCount) days ago"
                }
                return (result == expectedString)
                    <?> "Interval \(interval)s: expected '\(expectedString)' but got '\(result)'"
            }
    }

    // MARK: - Property 11c: Singular vs plural grammar

    @Test("Count of 1 uses singular form, count > 1 uses plural form")
    func singularPluralGrammar() {
        property("For any interval, count == 1 produces singular unit, count > 1 produces plural")
            <- forAll(timeIntervalGen) { interval in
                let date = self.referenceDate.addingTimeInterval(-Double(interval))
                let result = self.formatter.format(date, relativeTo: self.referenceDate)

                // Determine expected count and unit
                let expectedCount: Int
                let singularUnit: String
                let pluralUnit: String
                if interval >= 86400 {
                    expectedCount = interval / 86400
                    singularUnit = "day"
                    pluralUnit = "days"
                } else if interval >= 3600 {
                    expectedCount = interval / 3600
                    singularUnit = "hour"
                    pluralUnit = "hours"
                } else if interval >= 60 {
                    expectedCount = interval / 60
                    singularUnit = "minute"
                    pluralUnit = "minutes"
                } else {
                    expectedCount = interval
                    singularUnit = "second"
                    pluralUnit = "seconds"
                }

                let expectedString: String
                if expectedCount == 1 {
                    expectedString = "1 \(singularUnit) ago"
                } else {
                    expectedString = "\(expectedCount) \(pluralUnit) ago"
                }

                return (result == expectedString)
                    <?> "Interval \(interval)s: expected '\(expectedString)' but got '\(result)'"
            }
    }

    // MARK: - Property 11d: Output format always matches "N unit(s) ago" pattern

    @Test("Output always matches the pattern '<count> <unit> ago'")
    func outputFormatConsistency() {
        property("For any interval, output matches the format '<number> <unit> ago'")
            <- forAll(timeIntervalGen) { interval in
                let date = self.referenceDate.addingTimeInterval(-Double(interval))
                let result = self.formatter.format(date, relativeTo: self.referenceDate)

                // Verify the output ends with " ago"
                let endsWithAgo = result.hasSuffix(" ago")

                // Verify the output starts with a number
                let parts = result.split(separator: " ")
                let hasThreeParts = parts.count == 3
                let startsWithNumber = parts.first.flatMap { Int(String($0)) } != nil

                // Verify the middle part is a valid unit
                let validUnits = ["second", "seconds", "minute", "minutes", "hour", "hours", "day", "days"]
                let hasValidUnit = parts.count >= 2 && validUnits.contains(String(parts[1]))

                return (endsWithAgo <?> "Output '\(result)' doesn't end with ' ago'")
                    ^&&^
                    (hasThreeParts <?> "Output '\(result)' doesn't have exactly 3 parts")
                    ^&&^
                    (startsWithNumber <?> "Output '\(result)' doesn't start with a number")
                    ^&&^
                    (hasValidUnit <?> "Output '\(result)' doesn't contain a valid unit")
            }
    }

    // MARK: - Property 11e: Boundary precision at unit transitions

    @Test("Exact boundary values select the higher unit")
    func boundaryValuesSelectHigherUnit() {
        // Generator for exact boundary values
        let boundaryGen = Gen<Int>.fromElements(of: [60, 3600, 86400])

        property("Exact boundary values (60, 3600, 86400) use the higher unit")
            <- forAll(boundaryGen) { interval in
                let date = self.referenceDate.addingTimeInterval(-Double(interval))
                let result = self.formatter.format(date, relativeTo: self.referenceDate)

                switch interval {
                case 60:
                    return (result == "1 minute ago")
                        <?> "60s should be '1 minute ago' but got '\(result)'"
                case 3600:
                    return (result == "1 hour ago")
                        <?> "3600s should be '1 hour ago' but got '\(result)'"
                case 86400:
                    return (result == "1 day ago")
                        <?> "86400s should be '1 day ago' but got '\(result)'"
                default:
                    return false <?> "Unexpected boundary value: \(interval)"
                }
            }
    }
}
