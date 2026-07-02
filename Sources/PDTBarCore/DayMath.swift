import Foundation

func currentDayString() -> String {
    dayString(from: Date())
}

func dayString(_ day: String, addingDays days: Int) -> String {
    let formatter = dayFormatter()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let date = formatter.date(from: day),
          let shifted = calendar.date(byAdding: .day, value: days, to: date)
    else {
        return day
    }
    return dayString(from: shifted)
}

func dayString(from date: Date) -> String {
    dayFormatter().string(from: date)
}

func dayFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}

func dayPrefix(_ dateTime: String) -> String {
    String(dateTime.prefix(10))
}
