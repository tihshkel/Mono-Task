import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
    checks += 1
}
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
func date(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: text)!
}
let now = date("2026-10-21T06:00:00Z")  // Wednesday, 08:00 Berlin, before the DST transition.
let focusID = UUID()
let otherID = UUID()
let tag = ReminderTag(id: focusID, name: "Учёба", weekdays: [4])
let first = UUID()
let tasks = [
    ReminderTask(
        id: first, title: "Первая", date: now.addingTimeInterval(120), done: false, priority: true, tagIDs: [focusID],
        order: 1),
    ReminderTask(id: UUID(), title: "Без контекста", date: nil, done: false, priority: false, tagIDs: [], order: 0),
    ReminderTask(
        id: UUID(), title: "Другой контекст", date: now.addingTimeInterval(-100), done: false, priority: false,
        tagIDs: [otherID], order: 2),
    ReminderTask(
        id: UUID(), title: "Выполнена", date: now.addingTimeInterval(200), done: true, priority: true,
        tagIDs: [focusID], order: 0),
]
var p = NotificationPreferences()
func plans() -> [PlannedNotification] {
    NotificationPlanner.plans(tasks: tasks, tags: [tag], preferences: p, now: now, calendar: calendar)
}
check(plans().isEmpty, "Master switch must cancel every scheduled notification")
p.enabled = true
check(plans().count == 1, "Ignore completed, missing-date and past reminders")
check(plans().first?.taskID == first, "Keep task ID for notification routing")
check(plans().first?.identifier == "monotask.task.\(first.uuidString)", "Use stable replacement identifiers")
check(plans().first?.date == tasks.first?.date, "Preserve the selected reminder instant")
p.taskReminders = false
check(plans().isEmpty, "Task switch must cancel task reminders")
p.morningPlan = true
p.weekdays = [4]
let morning = plans()
check(morning.count == 2, "Only two Wednesdays within 14 days")
check(morning.allSatisfy { $0.taskID == nil }, "Morning tap must route to the plan, not an arbitrary task")
check(morning.first!.body.contains("Учёба"), "Show the scheduled focus")
check(morning.first!.body.contains("Первая"), "Include focus tasks")
check(morning.first!.body.contains("Без контекста"), "Include untagged tasks like the focus screen")
check(!morning.first!.body.contains("Другой контекст"), "Exclude tasks from other contexts on a focus day")
check(!morning.first!.body.contains("Выполнена"), "Never show completed tasks in a morning plan")
check(morning.allSatisfy { calendar.component(.hour, from: $0.date) == 9 }, "Preserve local 09:00 across DST")
check(
    morning[1].date.timeIntervalSince(morning[0].date) == 7 * 86400 + 3600,
    "Use calendar days instead of fixed 24-hour offsets")
p.morningScope = "all"
check(plans().first!.body.contains("Другой контекст"), "All scope includes other contexts")
p.morningScope = "priority"
check(
    plans().first!.body.contains("Первая") && !plans().first!.body.contains("Без контекста"),
    "Priority scope is restricted")
p.morningScope = "all"
p.taskCount = 1
check(
    plans().first!.body.contains("Первая") && !plans().first!.body.contains("Без контекста"),
    "Priority first; limit task names")
p.showPreview = false
p.taskReminders = true
check(
    plans().allSatisfy { !$0.body.contains("Первая") && !$0.body.contains("Учёба") },
    "Privacy hides task and focus names in every notification")
p.weekdays = []
check(plans().count == 1, "No weekdays disables only the morning plan")
p.weekdays = [1, 2, 3, 4, 5, 6, 7]
p.taskReminders = false
check(plans().count == 14, "Morning plan has a bounded 14-day horizon")
p.morningHour = 7
check(plans().count == 13, "Do not schedule a morning plan in the past today")
p.morningPlan = false
p.taskReminders = true
p.showPreview = true
func earlyPlans(_ lead: Int?, due: Date = now.addingTimeInterval(7_200)) -> [PlannedNotification] {
    let task = ReminderTask(
        id: first, title: "Дедлайн", date: due, done: false, priority: false, tagIDs: [], order: 0, minutesBefore: lead)
    return NotificationPlanner.plans(tasks: [task], tags: [], preferences: p, now: now, calendar: calendar)
}
check(
    earlyPlans(60).first?.date == now.addingTimeInterval(3_600),
    "Notify an hour before the deadline, not at the deadline")
check(earlyPlans(0).first?.date == now.addingTimeInterval(7_200), "Zero preserves at-deadline behavior")
check(earlyPlans(nil).isEmpty, "A deadline can exist without a notification")
check(earlyPlans(180).isEmpty, "Never move an elapsed early reminder to the deadline")
check(earlyPlans(120).isEmpty, "Do not schedule a reminder exactly at now")
check(earlyPlans(-1).isEmpty && earlyPlans(525_601).isEmpty, "Reject invalid imported offsets")
check(
    earlyPlans(60).first?.identifier == earlyPlans(30).first?.identifier,
    "Rescheduling replaces the same task notification")
check(earlyPlans(60).first?.body.contains("1 ч.") == true, "Explain the remaining time")
let winterDeadline = date("2026-10-25T02:30:00Z")
check(
    earlyPlans(120, due: winterDeadline).first?.date == winterDeadline.addingTimeInterval(-7_200),
    "An elapsed-time lead remains two hours across DST")
p.showPreview = false
check(earlyPlans(60).first?.body.contains("Дедлайн") == false, "Privacy also hides deadline task titles")
p.enabled = false
check(plans().isEmpty, "Disabling after configuration clears both kinds")
print("Passed \(checks) notification planner checks")
