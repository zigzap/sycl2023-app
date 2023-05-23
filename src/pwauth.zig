const std = @import("std");
const zap = @import("zap");
const Lookup = std.StringHashMap([]const u8);

const auth_lock_token_table = false;
const auth_lock_pw_table = false;

// see the source for more info
pub const Authenticator = zap.UserPassSessionAuth(
    Lookup,
    auth_lock_pw_table, // we may set this to true if we expect our username -> password map to change
    auth_lock_token_table, // we may set this to true to have session tokens deleted server-side on logout
);

const MaxFileSize = 10 * 1024;

allocator: std.mem.Allocator,
map: *Lookup,
authenticator: Authenticator,
contents: []const u8,

const Self = @This();

pub fn init(allocator: std.mem.Allocator, pwfile: []const u8, loginpagepath: []const u8) !Self {
    var map = try allocator.create(Lookup);
    map.* = Lookup.init(allocator);

    const contents = try std.fs.cwd().readFileAlloc(allocator, pwfile, MaxFileSize);
    var it = std.mem.split(u8, contents, "\n");
    std.debug.print("\nAvailable users:\n", .{});
    while (it.next()) |line| {
        if (std.mem.indexOf(u8, line, ":")) |pos| {
            const username = std.mem.trim(u8, line[0..pos], " \t");
            const password = std.mem.trim(u8, line[pos + 1 ..], " \t\n");
            try map.put(username, password);
            std.debug.print("    `{s}`: **********\n", .{username});
        }
    }

    return .{
        .allocator = allocator,
        .map = map,
        .authenticator = try Authenticator.init(
            allocator,
            map,
            .{
                .usernameParam = "username",
                .passwordParam = "password",
                .loginPage = loginpagepath,
                .cookieName = "zap-session",
            },
        ),
        .contents = contents,
    };
}

pub fn deinit(self: *Self) void {
    self.map.deinit();
    self.allocator.destroy(self.map);
    self.authenticator.deinit();
    self.allocator.free(self.contents);
}

test "it" {
    var a = std.testing.allocator;

    // create simple pw file
    const contents =
        \\ rene : rocks.ai
        \\ allyourcodebase : belongstous
    ;
    const filename = "xxxxfile.xxx";
    try std.fs.cwd().writeFile(filename, contents);

    var x = try Self.init(a, filename);
    defer x.deinit();

    const pw1 = x.map.get("rene");
    const pw2 = x.map.get("allyourcodebase");

    try std.testing.expectEqualStrings("rocks.ai", pw1.?);
    try std.testing.expectEqualStrings("belongstous", pw2.?);
    try std.fs.cwd().deleteFile(filename);
}
