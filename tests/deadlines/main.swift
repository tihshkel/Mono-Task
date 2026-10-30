import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}
let encoder = JSONEncoder()
let decoder = JSONDecoder()
let id = UUID()
let disabled = TaskItemDTO(id: id, title: "Deadline", reminderMinutesBefore: nil)
let encoded = try encoder.encode(disabled)
let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
check(object["due_date"] is NSNull, "Removing a deadline explicitly clears it on the server")
check(object["reminder_minutes_before"] is NSNull, "Disabling a reminder explicitly syncs null")
let roundTrip = try decoder.decode(TaskItemDTO.self, from: encoded)
check(
    roundTrip.reminderMinutesBefore == nil && roundTrip.includesReminderTiming, "Preserve explicit off across devices")
let legacy = try decoder.decode(TaskItemDTO.self, from: Data("{\"id\":\"\(id)\"}".utf8))
check(
    legacy.reminderMinutesBefore == 0 && !legacy.includesReminderTiming,
    "Legacy tasks retain their original at-deadline notification")
var fallback = disabled
fallback.includesReminderTiming = false
let fallbackObject = try JSONSerialization.jsonObject(with: encoder.encode(fallback)) as! [String: Any]
check(fallbackObject["reminder_minutes_before"] == nil, "Older schemas can still receive task edits")
let early = TaskItemDTO(
    id: id, title: "Early", dueDate: Date(timeIntervalSince1970: 1_800_000_000), reminderMinutesBefore: 90)
let earlyRoundTrip = try decoder.decode(TaskItemDTO.self, from: encoder.encode(early))
check(
    earlyRoundTrip.reminderMinutesBefore == 90 && earlyRoundTrip.dueDate == early.dueDate,
    "Custom lead and deadline survive cloud encoding")
print("Passed \(checks) deadline sync encoding checks")
