import Foundation

// Compiled against the real source files, not copies, so a change in the app breaks the test.
// Covers the places the build directive said tests earn their place: date parsing and the
// model's date handling. View layout is deliberately untested.

var failures = 0
@MainActor func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    if condition { print("  ok    \(label)") }
    else { failures += 1; print("  FAIL  \(label) \(detail)") }
}

print("DateParser: pulls a date out and tightens the title")
do {
    let r = DateParser.parse("call the plumber tomorrow")
    check("extracts a date", r.due != nil)
    check("strips the date phrase", !r.title.lowercased().contains("tomorrow"), "got: \(r.title)")
    check("keeps the subject", r.title.lowercased().contains("plumber"), "got: \(r.title)")
}
do {
    let r = DateParser.parse("email Sam about the invoice before Friday")
    check("drops the trailing connective", !r.title.lowercased().hasSuffix("before"), "got: \(r.title)")
    check("keeps the subject", r.title.lowercased().contains("invoice"), "got: \(r.title)")
}
do {
    let r = DateParser.parse("water the fig")
    check("no date means no date", r.due == nil)
    check("title survives untouched", r.title == "water the fig", "got: \(r.title)")
}
do {
    let r = DateParser.parse("   ")
    check("blank input is safe", r.due == nil && r.title.isEmpty)
}

print("IntelligenceBridge.parseDate: the model returns bare dates as often as datetimes")
do {
    check("bare date parses", IntelligenceBridge.parseDate("2026-08-15") != nil)
    if let d = IntelligenceBridge.parseDate("2026-08-15") {
        let h = Calendar.current.component(.hour, from: d)
        check("bare date means 9am", h == 9, "got hour \(h)")
    }
    check("full ISO8601 parses", IntelligenceBridge.parseDate("2026-08-15T17:00:00Z") != nil)
    check("local datetime parses", IntelligenceBridge.parseDate("2026-08-15T17:00:00") != nil)
    check("garbage is nil", IntelligenceBridge.parseDate("not a date") == nil)
    check("empty is nil", IntelligenceBridge.parseDate("") == nil)
}

print(failures == 0 ? "\nPASS" : "\nFAIL: \(failures) assertion(s)")
exit(failures == 0 ? 0 : 1)
