//! The participant pool
//!
//! You initialize the pool with a fixed number of participants to prepare for in `init()`.
//! When a participant logs in, you request a new Participant via `newParticipant()`.
//! This fails if all prepared participants are already exhausted.
//!
//! The pool is realized with a backing array. We can lock-free read from it
//! because our usage pattern supports non-concurrency per participant.
//! When writing or creating new participants (logging in) though, we lock.

const std = @import("std");
const jutils = @import("jsonutils.zig");

allocator: std.mem.Allocator = undefined,
current_participant_id: usize = 0,
participants: []Participant,
lock: std.Thread.Mutex = .{},

/// a JSON parser for the entire collection of participants
/// we (seem to) need to keep it in memory if we want to hold on to parsed JSON
/// values.
json_parser: ?std.json.Parser = null,
/// JSON parsing result - need to hold on to this once used.
json_parsed: ?std.json.ValueTree = null,

pub const Self = @This();

/// Creating a new participant may fail if all the pool's prepared participants
/// have been exhausted.
const ParticipantError = error{
    /// no prepared participant left to create a new participant
    Insert,
    /// getParticipant with wrong id
    OutOfBounds,
    /// not implemented
    NotImplemented,
    /// error parsing the participant id
    IdParseError,
    /// json (de)-serialization error. E.g. participantid in JSON does not match
    /// the expected one of the existing participant.
    JsonError,
};

/// General info for /login
/// TODO: unused in sycl app
pub const LoginInfo = struct {
    /// Unix time the participant landed here with a panel id
    servertime_login: usize,
    /// Unix time the participant landed here with a panel id, in ISO string format
    servertime_login_iso: ?[]const u8 = null,
    /// The time the experiment started for this participant
    servertime_start: ?usize = null,
    /// The time the experiment started for this participant, in ISO string format
    servertime_start_iso: ?[]const u8 = null,
};

/// A single participant as constructed by `newParticipant()`.
pub const Participant = struct {
    allocator: std.mem.Allocator,
    /// unique participant id, assigned by `newParticipant()`.
    participantid: usize,
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

    pub fn init(a: std.mem.Allocator, participantid: usize) !Participant {
        return .{
            .allocator = a,
            .participantid = participantid,
            .appstate = std.json.Value{ .object = std.json.ObjectMap.init(a) },
            .parsers_to_deinit = try std.ArrayList(*std.json.Parser).initCapacity(a, 10),
            .valuetrees_to_deinit = try std.ArrayList(*std.json.ValueTree).initCapacity(a, 10),
        };
    }

    pub fn deinit(self: *Participant) void {
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
        self.appstate.object.deinit();
    }

    pub fn updateAppdataFromJSON(self: *Participant, json: []const u8) !void {
        var parser = try self.allocator.create(std.json.Parser);
        parser.* = std.json.Parser.init(self.allocator, .alloc_always); // copy strings

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
                .object => |appdata| {
                    // iterate over appdata and update participant's appdata
                    var it = appdata.iterator();
                    while (it.next()) |pair| {
                        try self.appstate.object.put(pair.key_ptr.*, pair.value_ptr.*);
                    }
                },
                else => return ParticipantError.JsonError,
            }
        }
    }

    pub fn jsonStringify(
        self: *const Participant,
        options: std.json.StringifyOptions,
        out_stream: anytype,
    ) @TypeOf(out_stream).Error!void {
        _ = options;
        return std.json.stringify(.{
            .participantid = self.participantid,
            .current_task_id = self.current_task_id,
            .appstate = self.appstate,
        }, .{}, out_stream);
    }

    /// overwrite / initialize this participant's state by what JSON says (load from disk)
    pub fn restoreStateFromJson(self: *Participant, j: std.json.Value) !void {
        switch (j) {
            .object => |_| {
                const loaded_participantid = try jutils.getJsonUsizeValue(j, "participantid");
                self.participantid = loaded_participantid;
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

/// Creates the pool of prepared participants.
pub fn init(a: std.mem.Allocator, prepareHowMany: usize) !Self {
    return .{
        .allocator = a,
        .participants = try a.alloc(Participant, prepareHowMany),
    };
}

/// updates the state of this pool to the one persisted into json.
/// the pool must be already created at this time.
pub fn restoreStateFromJson(self: *Self, json: []const u8) !void {
    // parser needs to copy strings as the json text is likely to be freed after parsing
    self.json_parser = std.json.Parser.init(self.allocator, .alloc_always);
    self.json_parsed = try self.json_parser.?.parse(json);

    // json_parsed is supposed to be an array
    if (self.json_parsed) |parsed| {
        switch (parsed.root) {
            .array => |a| {
                // do the actual parsing
                const l = a.items.len;
                if (l > self.participants.len) {
                    return ParticipantError.JsonError;
                }
                for (parsed.root.array.items, 0..) |u, i| {
                    self.participants[i] = try Participant.init(self.allocator, i);
                    try self.participants[i].restoreStateFromJson(u);
                }
                self.current_participant_id = a.items.len;
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
    // deinit all participants
    var i: usize = 0;
    while (i < self.current_participant_id) : (i += 1) {
        std.debug.print("deiniting participant {d}\n", .{i});
        self.participants[i].deinit();
    }
    self.allocator.free(self.participants);
    std.debug.print("deinited all participants\n", .{});
}

/// Thread-safely creating a new participant.
/// This may fail if all the pool's prepared participants have been exhausted.
pub fn newParticipant(self: *Self) !*Participant {
    self.lock.lock();
    defer self.lock.unlock();

    if (self.current_participant_id >= self.participants.len) {
        return ParticipantError.Insert;
    }

    self.participants[self.current_participant_id] = try Participant.init(self.allocator, self.current_participant_id);

    var participant = &self.participants[self.current_participant_id];

    // advance id for participant to create next
    self.current_participant_id += 1;
    return participant;
}

pub fn getParticipant(self: *Self, id: usize) !*Participant {
    if (id >= self.current_participant_id or id >= self.participants.len) {
        return ParticipantError.OutOfBounds;
    }
    // assert id >= 1 <= self.participants.len
    return &self.participants[id]; // we return participant 0 for id 1
}

pub fn getParticipantFromIdString(self: *Self, id: []const u8) !*Participant {
    if (std.fmt.parseUnsigned(usize, id, 10)) |participant_id| {
        return self.getParticipant(participant_id);
    } else |_| {
        return ParticipantError.IdParseError;
    }
}

pub fn jsonStringify(
    self: *const Self,
    options: std.json.StringifyOptions,
    out_stream: anytype,
) @TypeOf(out_stream).Error!void {
    try out_stream.writeByte('[');
    var child_options = options;
    if (child_options.whitespace.indent != .none) {
        child_options.whitespace.indent_level += 1;
    }
    for (0..self.current_participant_id) |i| {
        if (i != 0) {
            try out_stream.writeByte(',');
        }
        if (child_options.whitespace.indent != .none) {
            try child_options.whitespace.outputIndent(out_stream);
        }
        try self.participants[i].jsonStringify(child_options, out_stream);
    }
    if (self.current_participant_id != 0) {
        if (options.whitespace.indent != .none) {
            try options.whitespace.outputIndent(out_stream);
        }
    }
    try out_stream.writeByte(']');
    return;
}

test "participants" {
    const appdata_json =
        \\{
        \\     "x" : {
        \\         "x": 1,
        \\         "y": "world"
        \\     }
        \\ }
    ;
    var a = std.testing.allocator;
    var the_participants = try init(a, 1);
    defer the_participants.deinit();
    var p = try the_participants.newParticipant();
    try std.testing.expect(p.participantid == 0);
    try p.updateAppdataFromJSON(appdata_json);
    try std.testing.expect(the_participants.current_participant_id == 1);
    var err = the_participants.newParticipant();
    try std.testing.expectError(ParticipantError.Insert, err);
}
