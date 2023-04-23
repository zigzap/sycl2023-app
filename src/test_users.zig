const std = @import("std");
const Users = @import("users.zig");

const alloc = std.testing.allocator;

test "json_in_out" {
    const s =
        \\ [
        \\    { "userid": 0, "current_task_id": "0", "appstate": { "coolness" : "yeah" } },
        \\    { "userid": 1, "current_task_id": "0", "appstate": {} },
        \\    { "userid": 2, "current_task_id": "0", "appstate": {} }
        \\ ]
    ;

    var users = try Users.init(alloc, 50);
    defer users.deinit();

    try users.restoreStateFromJson(s);
    const out = try std.json.stringifyAlloc(alloc, users, .{});
    defer alloc.free(out);

    if (false) {
        std.debug.print("{any}\n", .{users.users[0..users.current_user_id]});
        std.debug.print("\n{s}\n", .{out});
    }

    const expected =
        \\[{"userid":0,"current_task_id":"0","appstate":{"coolness":"yeah"}},{"userid":1,"current_task_id":"0","appstate":{}},{"userid":2,"current_task_id":"0","appstate":{}}]
    ;
    try std.testing.expectEqualStrings(out, expected);
    try std.testing.expect(users.current_user_id == 3);
}
