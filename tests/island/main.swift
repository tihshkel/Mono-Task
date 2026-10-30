import Foundation

private var checks = 0
@MainActor func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}

let first = UUID()
let second = UUID()
let third = UUID()
var queue = IslandQueue()
queue.add(first, makeActive: true)
queue.add(second, makeActive: false)
queue.add(first, makeActive: false)
check(queue.ids == [first, second] && queue.activeID == first, "Drops must be idempotent and preserve queue order")
queue.add(third, makeActive: true)
check(queue.activeID == third && queue.ids == [first, second, third], "Focus drop selects without reordering")
queue.next()
check(queue.activeID == first, "Next wraps around the queue")
queue.remove(first)
check(queue.activeID == second, "Completing a task selects its successor")
queue.reconcile(availableIDs: [third])
check(queue.ids == [third] && queue.activeID == third, "Remote deletion/completion must clear stale references")
queue.reconcile(availableIDs: [])
check(queue.activeID == nil && queue.ids.isEmpty, "An empty queue has no dangling selection")
queue.next()
check(queue.activeID == nil, "Next on an empty queue is safe")

let start = Date(timeIntervalSince1970: 1_800_000_000)
var clock = IslandFocusClock()
clock.start(minutes: 25, taskID: first, at: start)
check(clock.remaining(at: start.addingTimeInterval(600)) == 900, "Countdown must use elapsed wall time")
clock.pause(at: start.addingTimeInterval(600))
check(!clock.isRunning && clock.remaining(at: start.addingTimeInterval(10_000)) == 900, "Paused clocks do not drift")
clock.resume(at: start.addingTimeInterval(10_000))
let restored = try JSONDecoder().decode(IslandFocusClock.self, from: JSONEncoder().encode(clock))
check(
    restored.taskID == first && restored.remaining(at: start.addingTimeInterval(10_400)) == 500,
    "Relaunch must retain both session ownership and deadline")
check(!clock.finishIfNeeded(at: start.addingTimeInterval(10_899)), "Do not complete before the deadline")
check(clock.finishIfNeeded(at: start.addingTimeInterval(20_000)), "Wake after a long sleep completes once")
check(!clock.finishIfNeeded(at: start.addingTimeInterval(20_001)), "Completion is emitted only once")
clock.reset(minutes: 45)
check(!clock.hasStarted && clock.taskID == nil && clock.remaining(at: start) == 2700, "Reset clears session ownership")

// A temporary defaults suite simulates switching accounts without touching real app preferences.
let suite = "monotask.island.tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
var accountA = IslandQueue()
accountA.add(first, makeActive: true)
defaults.set(try JSONEncoder().encode(accountA), forKey: "accountA.queue")
defaults.set(try JSONEncoder().encode(IslandQueue()), forKey: "accountB.queue")
let accountB = try JSONDecoder().decode(IslandQueue.self, from: defaults.data(forKey: "accountB.queue")!)
let reopenedA = try JSONDecoder().decode(IslandQueue.self, from: defaults.data(forKey: "accountA.queue")!)
check(accountB.ids.isEmpty && reopenedA.activeID == first, "Accounts must never share a quick-access queue")
var preferences = IslandPreferences()
preferences.dropAction = .enqueue
preferences.clickAction = .timer
preferences.animations = false
let restoredPreferences = try JSONDecoder().decode(IslandPreferences.self, from: JSONEncoder().encode(preferences))
check(preferences == restoredPreferences, "Interaction and accessibility preferences must survive relaunch")
print("Island: \(checks) checks passed")
