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

// if we restore, the json buf will go in there
json_source_buf: []const u8 = undefined,

/// JSON parsing result - need to hold on to this once used.
json_parsed: ?std.json.Parsed(std.json.Value) = null,

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
    values_to_deinit: std.ArrayList(*std.json.Parsed(std.json.Value)) = undefined,

    /// the underlying json buffers have to be kept, because std.json.Value only has references to the buffer
    buffers_to_deinit: std.ArrayList([]const u8) = undefined,

    /// Panel ID, such as: prolific ID
    panel_id: ?[]const u8 = null,

    const Self = @This();

    pub fn init(a: std.mem.Allocator, participantid: usize) !Participant {
        return .{
            .allocator = a,
            .participantid = participantid,
            .appstate = std.json.Value{ .object = std.json.ObjectMap.init(a) },
            .values_to_deinit = try std.ArrayList(*std.json.Parsed(std.json.Value)).initCapacity(a, 10),
            .buffers_to_deinit = try std.ArrayList([]const u8).initCapacity(a, 10),
        };
    }

    pub fn deinit(self: *Participant) void {
        for (self.values_to_deinit.items, 0..) |vt, i| {
            std.debug.print("deiniting parsed json {d} {any}\n", .{ i, vt });
            vt.deinit();
            std.debug.print("deinitED parsed json {d}\n", .{i});
            self.allocator.destroy(vt);
            std.debug.print("destroyed parsed json {d}\n", .{i});
        }
        self.values_to_deinit.deinit();

        for (self.buffers_to_deinit.items) |buffer| {
            self.allocator.free(buffer);
        }
        self.buffers_to_deinit.deinit();

        self.appstate.object.deinit();
    }

    pub fn updateAppdataFromJSON(self: *Participant, json: []const u8) !void {
        // create the Parsed on the heap, then add it to values_to_deinit
        var parsed: *std.json.Parsed(std.json.Value) = try self.allocator.create(std.json.Parsed(std.json.Value));

        // also, keep the json buffer so strings don't become invalidated
        const json_copy = try self.allocator.dupe(u8, json);
        try self.buffers_to_deinit.append(json_copy);

        parsed.* = try std.json.parseFromSlice(std.json.Value, self.allocator, json_copy, .{});
        // add it to values_to_deinit
        try self.values_to_deinit.append(parsed);
        switch (parsed.value) {
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

    pub fn isFinal(self: *const Participant) bool {
        if (self.appstate.object.get("finished")) |_| {
            return true;
        }
        return false;
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
    self.json_source_buf = try self.allocator.dupe(u8, json);
    self.json_parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, self.json_source_buf, .{});

    // json_parsed is supposed to be an array
    if (self.json_parsed) |parsed| {
        switch (parsed.value) {
            .array => |a| {
                // do the actual parsing
                const l = a.items.len;
                if (l > self.participants.len) {
                    return ParticipantError.JsonError;
                }
                for (parsed.value.array.items, 0..) |u, i| {
                    self.participants[i] = try Participant.init(self.allocator, i);
                    try self.participants[i].restoreStateFromJson(u);
                }
                self.current_participant_id = l;
                std.log.debug("READ {} participants!\n", .{l});
            },
            else => return jutils.JsonError.InvalidType_ArrayExpected,
        }
    }
}

/// Call this to avoid mem leaks.
pub fn deinit(self: *Self) void {
    // deinit all participants
    var i: usize = 0;
    while (i < self.current_participant_id) : (i += 1) {
        std.debug.print("deiniting participant {d}\n", .{i});
        self.participants[i].deinit();
    }
    self.allocator.free(self.participants);

    // deinit the loaded json stuff
    if (self.json_parsed) |*p| {
        p.deinit();
    }
    self.allocator.free(self.json_source_buf);
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
    for (0..self.current_participant_id) |i| {
        if (i != 0) {
            try out_stream.writeByte(',');
        }
        try self.participants[i].jsonStringify(options, out_stream);
    }
    try out_stream.writeByte(']');
    return;
}

pub const statCounts = struct {
    active: usize = 0,
    finished: usize = 0,
    total: usize = 0,
};

pub fn statCounters(self: *Self) statCounts {
    var ret = statCounts{};
    self.lock.lock();
    defer self.lock.unlock();
    for (0..self.current_participant_id) |i| {
        ret.total += 1;
        const participant = self.participants[i];
        if (participant.isFinal()) {
            ret.finished += 1;
        } else {
            ret.active += 1;
        }
    }
    return ret;
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
