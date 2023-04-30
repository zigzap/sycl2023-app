//! The user pool
//!
//! You initialize the pool with a fixed number of users to prepare for in `init()`.
//! When a user logs in, you request a new User via `newUser()`. This fails if
//! all prepared users are already exhausted.
//!
//! The pool is realized with a backing array. We can lock-free read from it
//! because our usage pattern supports non-concurrency per user. When writing
//! or creating new users (logging in) though, we lock.

const std = @import("std");
const jutils = @import("jsonutils.zig");

allocator: std.mem.Allocator = undefined,
current_user_id: usize = 0,
users: []User,
lock: std.Thread.Mutex = .{},

/// a JSON parser for the entire collection of users
/// we (seem to) need to keep it in memory if we want to hold on to parsed JSON
/// values.
json_parser: ?std.json.Parser = null,
/// JSON parsing result - need to hold on to this once used.
json_parsed: ?std.json.ValueTree = null,

pub const Self = @This();

/// Creating a new user may fail if all the pool's prepared users have been
/// exhausted.
const UserError = error{
    /// no prepared user left to create a new user
    Insert,
    /// getUser with wrong id
    OutOfBounds,
    /// not implemented
    NotImplemented,
    /// error parsing the user id
    IdParseError,
    /// json (de)-serialization error. E.g. userid in JSON does not match the
    /// expected one of the existing user.
    JsonError,
};

/// General info for /login
pub const LoginInfo = struct {
    /// Unix time the user landed here with a panel id
    servertime_login: usize,
    /// Unix time the user landed here with a panel id, in ISO string format
    servertime_login_iso: ?[]const u8 = null,
    /// The time the experiment started for this user
    servertime_start: ?usize = null,
    /// The time the experiment started for this user, in ISO string format
    servertime_start_iso: ?[]const u8 = null,
};

/// A single user as constructed by `newUser()`.
pub const User = struct {
    allocator: std.mem.Allocator,
    /// unique user id, assigned by `newUser()`.
    userid: usize,
    /// tracks the id of the current task in the experiment
    current_task_id: []const u8 = "0",
    /// JSON object for dynamic storage of what the JS frontend wants to put there.
    appstate: std.json.Value = undefined,
    /// we hold on to the parsed appdata updates
    parsers_to_deinit: std.ArrayList(*std.json.Parser) = undefined,
    valuetrees_to_deinit: std.ArrayList(*std.json.ValueTree) = undefined,

    /// Panel ID, such as: prolific ID
    panel_id: ?[]const u8 = null,

    const Self = @This();

    pub fn init(a: std.mem.Allocator, userid: usize) !User {
        return .{
            .allocator = a,
            .userid = userid,
            .appstate = std.json.Value{ .Object = std.json.ObjectMap.init(a) },
            .parsers_to_deinit = try std.ArrayList(*std.json.Parser).initCapacity(a, 10),
            .valuetrees_to_deinit = try std.ArrayList(*std.json.ValueTree).initCapacity(a, 10),
        };
    }

    pub fn deinit(self: *User) void {
        for (self.parsers_to_deinit.items) |vt| {
            vt.deinit();
            self.allocator.destroy(vt);
        }

        for (self.valuetrees_to_deinit.items, 0..) |vt, i| {
            std.debug.print("deiniting valuetree {d} {any}\n", .{ i, vt });
            vt.deinit();
            std.debug.print("deinitED valuetree {d}\n", .{i});
            self.allocator.destroy(vt);
            std.debug.print("destroyed valuetree {d}\n", .{i});
        }

        self.valuetrees_to_deinit.deinit();
        self.parsers_to_deinit.deinit();
        self.appstate.Object.deinit();
    }

    pub fn updateAppdataFromJSON(self: *User, json: []const u8) !void {
        var parser = try self.allocator.create(std.json.Parser);
        parser.* = std.json.Parser.init(self.allocator, true); // copy strings

        // if we can't add to the destroy stack, we need to do so ourselves
        self.parsers_to_deinit.append(parser) catch |err| {
            parser.deinit();
            self.allocator.destroy(parser);
            return err;
        };

        var maybe_valueTree: ?std.json.ValueTree = try parser.parse(json);

        if (maybe_valueTree) |valueTree| {
            var alloced_value_tree = try self.allocator.create(std.json.ValueTree);
            alloced_value_tree.* = valueTree;

            // if we err out here, we need to destroy the valuetree ourselves
            self.valuetrees_to_deinit.append(alloced_value_tree) catch |err| {
                alloced_value_tree.deinit();
                self.allocator.destroy(alloced_value_tree);
                return err;
            };

            switch (alloced_value_tree.*.root) {
                .Object => |appdata| {
                    // iterate over appdata and update user's appdata
                    var it = appdata.iterator();
                    while (it.next()) |pair| {
                        try self.appstate.Object.put(pair.key_ptr.*, pair.value_ptr.*);
                    }
                },
                else => return UserError.JsonError,
            }
        }
    }

    pub fn jsonStringify(
        self: *const User,
        options: std.json.StringifyOptions,
        out_stream: anytype,
    ) @TypeOf(out_stream).Error!void {
        _ = options;
        return std.json.stringify(.{
            .userid = self.userid,
            .current_task_id = self.current_task_id,
            .appstate = self.appstate,
        }, .{}, out_stream);
    }

    /// overwrite / initialize this user's state by what JSON says (load from disk)
    pub fn restoreStateFromJson(self: *User, j: std.json.Value) !void {
        switch (j) {
            .Object => |_| {
                const loaded_userid = try jutils.getJsonUsizeValue(j, "userid");
                self.userid = loaded_userid;
                // todo: we could dupe() the string
                const current_task_id = try jutils.getJsonStringValue(j, "current_task_id");
                // todo: we could .move() the appstate
                const appstate = try jutils.getJsonObjectValue(j, "appstate");

                self.current_task_id = current_task_id;
                self.appstate = appstate;
            },
            else => return jutils.JsonError.InvalidType_ObjectExpected,
        }
    }
};

/// Creates the pool of prepared users.
pub fn init(a: std.mem.Allocator, prepareHowMany: usize) !Self {
    return .{
        .allocator = a,
        .users = try a.alloc(User, prepareHowMany),
    };
}

/// updates the state of this pool to the one persisted into json.
/// the pool must be already created at this time.
pub fn restoreStateFromJson(self: *Self, json: []const u8) !void {
    // parser needs to copy strings as the json text is likely to be freed after parsing
    self.json_parser = std.json.Parser.init(self.allocator, true);
    self.json_parsed = try self.json_parser.?.parse(json);

    // json_parsed is supposed to be an array
    if (self.json_parsed) |parsed| {
        switch (parsed.root) {
            .Array => |a| {
                // do the actual parsing
                const l = a.items.len;
                if (l > self.users.len) {
                    return UserError.JsonError;
                }
                for (parsed.root.Array.items, 0..) |u, i| {
                    try self.users[i].restoreStateFromJson(u);
                }
                self.current_user_id = a.items.len;
            },
            else => return jutils.JsonError.InvalidType_ArrayExpected,
        }
    }
}

/// Call this to avoid mem leaks.
pub fn deinit(self: *Self) void {
    if (self.json_parser) |*p| {
        p.deinit();
    }
    if (self.json_parsed) |*p| {
        p.deinit();
    }
    // deinit all users
    var i: usize = 0;
    while (i < self.current_user_id) : (i += 1) {
        std.debug.print("deiniting user {d}\n", .{i});
        self.users[i].deinit();
    }
    self.allocator.free(self.users);
    std.debug.print("deinited all users\n", .{});
}

/// Thread-safely creating a new user.
/// This may fail if all the pool's prepared users have been exhausted.
pub fn newUser(self: *Self) !*User {
    self.lock.lock();
    defer self.lock.unlock();

    if (self.current_user_id >= self.users.len) {
        return UserError.Insert;
    }

    self.users[self.current_user_id] = try User.init(self.allocator, self.current_user_id);

    var user = &self.users[self.current_user_id];

    // advance id for user to create next
    self.current_user_id += 1;
    return user;
}

pub fn getUser(self: *Self, id: usize) !*User {
    if (id >= self.current_user_id or id >= self.users.len) {
        return UserError.OutOfBounds;
    }
    // assert id >= 1 <= self.users.len
    return &self.users[id]; // we return user 0 for id 1
}

pub fn getUserFromIdString(self: *Self, id: []const u8) !*User {
    if (std.fmt.parseUnsigned(usize, id, 10)) |user_id| {
        return self.getUser(user_id);
    } else |_| {
        return UserError.IdParseError;
    }
}

pub fn jsonStringify(
    self: *const Self,
    options: std.json.StringifyOptions,
    out_stream: anytype,
) @TypeOf(out_stream).Error!void {
    try out_stream.writeByte('[');
    var child_options = options;
    if (child_options.whitespace) |*whitespace| {
        whitespace.indent_level += 1;
    }
    for (0..self.current_user_id) |i| {
        if (i != 0) {
            try out_stream.writeByte(',');
        }
        if (child_options.whitespace) |child_whitespace| {
            try child_whitespace.outputIndent(out_stream);
        }
        try self.users[i].jsonStringify(child_options, out_stream);
    }
    if (self.current_user_id != 0) {
        if (options.whitespace) |whitespace| {
            try whitespace.outputIndent(out_stream);
        }
    }
    try out_stream.writeByte(']');
    return;
}

test "users" {
    const appdata_json =
        \\{
        \\     "x" : {
        \\         "x": 1,
        \\         "y": "world"
        \\     }
        \\ }
    ;
    var a = std.testing.allocator;
    var the_users = try init(a, 1);
    defer the_users.deinit();
    var p = try the_users.newUser();
    try std.testing.expect(p.userid == 0);
    try p.updateAppdataFromJSON(appdata_json);
    try std.testing.expect(the_users.current_user_id == 1);
    var err = the_users.newUser();
    try std.testing.expectError(UserError.Insert, err);
}
