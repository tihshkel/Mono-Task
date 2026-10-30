import Foundation

var count = 0
@MainActor
func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    precondition(condition(), description)
    count += 1
}
let owner = UUID()
let guest = UUID()
let list = SharedList(id: UUID(), title: "Together", ownerID: owner, createdAt: .now)
let members = [
    SharedMember(listID: list.id, userID: owner, displayName: "Owner"),
    SharedMember(listID: list.id, userID: guest, displayName: "Guest"),
]
let task = SharedTask(listID: list.id, title: "Original", notes: "Before", assigneeID: guest, revision: 1)
let initial = SharedSnapshot(lists: [list], members: members, tasks: [task])
let code = "0123456789abcdef0123456789abcdef"
check(SharedInvite.parseCode(" \(code.uppercased())\n") == code, "Codes are normalized")
check(SharedInvite.parseCode("com.monotask.ios://join?code=\(code)") == code, "App invitation links parse")
check(SharedInvite.parseCode("https://evil.test/join?code=\(code)") == nil, "Unrelated links are not invitations")
check(
    SharedInvite.parseCode("com.monotask.ios://auth-callback?code=\(code)") == nil,
    "Authentication links cannot be treated as invitations")
check(SharedInvite.parseCode(String(repeating: "g", count: 32)) == nil, "Nonhex invitation input is rejected")
check(SharedInvite.parseCode("short") == nil, "Truncated codes are rejected")
let invite = SharedInvite(code: code, expiresAt: .now)
check(invite.url.absoluteString == "https://tihshkel.github.io/Mono-Task/join/#\(code)", "Shared URLs use the Mono-Task Pages site")
check(SharedInvite.parseCode(invite.url.absoluteString) == code, "HTTPS invitation links parse")
check(
    SharedInvite.parseCode("https://tihshkel.github.io/Mono-Task/join/#\(code.uppercased())") == code,
    "HTTPS codes normalize")
check(
    SharedInvite.parseCode("https://egoar777.github.io/MonoTask/join/#\(code)") == code,
    "Previously shared Pages links still parse")
for url in [
    "https://tihshkel.github.io/other/#\(code)",
    "https://tihshkel.github.io/MonoTask/join/#\(code)",
    "https://evil.test/Mono-Task/join/#\(code)",
    "http://tihshkel.github.io/Mono-Task/join/#\(code)",
    "https://tihshkel.github.io@evil.test/Mono-Task/join/#\(code)",
    "https://tihshkel.github.io/Mono-Task/join/?code=\(code)",
    "https://tihshkel.github.io/Mono-Task/join/#short",
    "https://egoar777.github.io/other/#\(code)",
    "https://egoar777.github.io/Mono-Task/join/#\(code)",
    "http://egoar777.github.io/MonoTask/join/#\(code)",
    "https://egoar777.github.io@evil.test/MonoTask/join/#\(code)",
    "https://egoar777.github.io/MonoTask/join/?code=\(code)",
] {
    check(SharedInvite.parseCode(url) == nil, "Invalid HTTPS invitations are rejected")
}
var cache = SharedCache(snapshot: initial)
var edit = task
edit.notes = "Offline edit"
cache.queue(edit)
check(cache.pending.count == 1, "Offline edits enter durable queue")
var secondEdit = edit
secondEdit.title = "Second edit"
cache.queue(secondEdit)
check(cache.pending.count == 1 && cache.pending[0].task.title == "Second edit", "Repeated offline edits coalesce")
cache.reconcile(initial)
check(
    cache.snapshot.tasks[0].notes == "Offline edit" && cache.pending[0].remoteVersion == nil,
    "Unchanged server does not overwrite offline edits")
var remoteEdit = task
remoteEdit.notes = "Other participant"
remoteEdit.revision = 2
cache.reconcile(SharedSnapshot(lists: [list], members: members, tasks: [remoteEdit]))
check(cache.pending[0].remoteVersion?.notes == "Other participant", "Conflicts keep the actual shared version")
check(cache.snapshot.tasks[0].notes == "Offline edit", "Conflicts preserve local content")
cache.resolve(task.id, keepLocal: true)
check(
    cache.pending[0].task.revision == 2 && cache.pending[0].remoteVersion == nil,
    "Explicit local resolution uses the latest revision")
let pending = cache.pending[0]
var saved = pending.task
saved.revision = 3
cache.acknowledge(pending, saved: saved)
check(
    cache.pending.isEmpty && cache.snapshot.tasks[0].revision == 3, "Acknowledgement updates queue and visible revision"
)
cache = SharedCache(snapshot: initial)
cache.queue(edit)
let sent = cache.pending[0]
cache.queue(secondEdit)
var response = edit
response.revision = 2
cache.acknowledge(sent, saved: response)
check(
    cache.pending.count == 1 && cache.pending[0].task.title == "Second edit",
    "In-flight acknowledgements cannot drop newer edits")
check(cache.pending[0].task.revision == 2, "Newer edits inherit acknowledged revision")
cache = SharedCache(snapshot: initial)
cache.queue(edit)
var committed = edit
committed.revision = 2
cache.reconcile(SharedSnapshot(lists: [list], members: members, tasks: [committed]))
check(cache.pending.isEmpty, "A lost HTTP response does not create a false conflict for identical content")
cache = SharedCache(snapshot: initial)
cache.queue(edit)
var deleted = task
deleted.revision = 2
deleted.deletedAt = .now
cache.reconcile(SharedSnapshot(lists: [list], members: members, tasks: [deleted]))
check(cache.pending[0].remoteVersion?.deletedAt != nil, "Remote deletions conflict with unsent local changes")
cache.resolve(task.id, keepLocal: true)
check(
    cache.pending[0].task.id != task.id && cache.pending[0].task.revision == 0,
    "Saving after remote deletion creates a copy, never resurrects the deleted ID")
cache.reconcile(SharedSnapshot())
check(
    cache.pending.isEmpty && cache.snapshot.tasks.isEmpty && cache.snapshot.members.isEmpty,
    "Revoked membership purges pending and cached shared content")
cache = SharedCache(snapshot: initial)
cache.queue(edit)
cache.reconcile(SharedSnapshot(lists: [list], members: [members[0]], tasks: [task]))
check(cache.pending[0].task.assigneeID == nil, "Removed participants cannot remain selected as assignees")
let data = try JSONEncoder().encode(cache)
let restored = try JSONDecoder().decode(SharedCache.self, from: data)
check(
    restored.pending.count == 1 && restored.pending[0].task.notes == "Offline edit",
    "Pending edits survive a disk-cache round trip")
cache.reconcile(SharedSnapshot(lists: [list], members: members, tasks: [remoteEdit]))
cache.resolve(task.id, keepLocal: false)
check(
    cache.pending.isEmpty && cache.snapshot.tasks[0].notes == "Other participant",
    "Explicit remote resolution clears local pending edits")
print("Passed \(count) shared cache and invitation checks")
