const std = @import("std");
const Participants = @import("participants.zig");

const alloc = std.testing.allocator;

test "json_in_out" {
    const s =
        \\ [
        \\    { "participantid": 0, "current_task_id": "0", "appstate": { "coolness" : "yeah" } },
        \\    { "participantid": 1, "current_task_id": "0", "appstate": {} },
        \\    { "participantid": 2, "current_task_id": "0", "appstate": {} }
        \\ ]
    ;

    var participants = try Participants.init(alloc, 50);
    defer participants.deinit();

    try participants.restoreStateFromJson(s);
    const out = try std.json.stringifyAlloc(alloc, participants, .{});
    defer alloc.free(out);

    if (false) {
        std.debug.print("{any}\n", .{participants.participants[0..participants.current_participant_id]});
        std.debug.print("\n{s}\n", .{out});
    }

    const expected =
        \\[{"participantid":0,"current_task_id":"0","appstate":{"coolness":"yeah"}},{"participantid":1,"current_task_id":"0","appstate":{}},{"participantid":2,"current_task_id":"0","appstate":{}}]
    ;
    try std.testing.expectEqualStrings(out, expected);
    try std.testing.expect(participants.current_participant_id == 3);
}
