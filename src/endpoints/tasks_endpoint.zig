const std = @import("std");
const zap = @import("zap");
const Tasks = @import("../tasks.zig");
const Participants = @import("../participants.zig");
const Participant = Participants.Participant;

const is_debug_build = @import("builtin").mode == std.builtin.Mode.Debug;

alloc: std.mem.Allocator = undefined,
endpoint: zap.SimpleEndpoint = undefined,
participants: Participants = undefined,
tasks: Tasks = undefined,
max_participants: usize,

pub const Self = @This();

// not using context / callback functions from mustache. we rather use prepared vars
pub const RenderContext = struct {
    // put stuff in there you want to refer in the json template
    participantid: isize,
};

pub fn init(
    a: std.mem.Allocator,
    task_path: []const u8,
    task_template_filn: []const u8,
    max_participants: usize,
) !Self {
    var ret: Self = .{
        .tasks = try Tasks.init(a, task_template_filn),
        .alloc = a,
        .endpoint = zap.SimpleEndpoint.init(.{
            .path = task_path,
            .get = getTask,
            .post = postTask,
            .put = null,
            .delete = null,
        }),
        .participants = try Participants.init(a, max_participants),
        .max_participants = max_participants,
    };
    return ret;
}

pub fn getParticipants(self: *Self) *Participants {
    return &self.participants;
}

pub fn getTasks(self: *Self) *Tasks {
    return &self.tasks;
}

pub fn getTaskEndpoint(self: *Self) *zap.SimpleEndpoint {
    return &self.endpoint;
}

fn taskIdFromPath(self: *Self, path: []const u8) ?[]const u8 {
    if (path.len >= self.endpoint.settings.path.len + 2) {
        if (path[self.endpoint.settings.path.len] != '/') {
            return null;
        }
        const idstr = path[self.endpoint.settings.path.len + 1 ..];
        return idstr;
    }
    return null;
}

fn getTask(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
    const self = @fieldParentPtr(Self, "endpoint", e);
    if (r.path) |p| {
        // /tasks
        if (p.len == e.settings.path.len) {
            return self.listTasks(r);
        }

        // /reload
        if (std.mem.endsWith(u8, p, "reload")) {
            self.reloadTasks(r);
        }

        std.log.debug("getTask 1\n", .{});
        // get participant id from query
        if (r.query) |q| {
            if (participantIdFromQuery(q)) |uid| {
                if (!std.mem.eql(u8, uid, "null")) {
                    std.debug.print("    ERROR Participant ID must be null, got: {s}\n", .{uid});
                    r.sendJson("{\"error\": \"invalid participant id\"}") catch return;
                    return;
                }
                if (self.taskIdFromPath(p)) |taskid| {
                    if (self.tasks.json_template.?.value.object.get(taskid)) |*task| {
                        if (is_debug_build) {
                            std.log.debug("getTask: dumping task...\n", .{});
                            task.dump();
                        }
                        var buf: [100 * 1024]u8 = undefined;
                        var fba = std.heap.FixedBufferAllocator.init(&buf);
                        var string = std.ArrayList(u8).init(fba.allocator());
                        if (std.json.stringify(task, .{}, string.writer())) {
                            // Not mustaching, since there's nothing to mustache
                            // in this example. E.g. no differing stimulus
                            // configuration, etc.
                            const template = string.items;
                            r.sendJson(template) catch return;
                        } else |err| {
                            std.debug.print("    Error: {any}\n", .{err});
                            r.setStatus(.not_found);
                            r.sendJson("{ \"status\": \"not found\"}") catch return;
                        }
                    } else {
                        std.log.debug("template.value.object has no key `{s}`!\n", .{taskid});
                        self.tasks.json_template.?.value.dump();
                        std.log.debug("\n", .{});
                    }
                } else {
                    std.log.debug("getTask error: no taskid\n", .{});
                }
            }
        } else {
            std.log.debug("getTask NO QUERY\n", .{});
        }
    }
}

fn postTask(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
    const self = @fieldParentPtr(Self, "endpoint", e);
    if (r.path) |p| {
        // get participant id from query
        if (r.query) |q| {
            std.debug.print("    post {s}?{s}\n", .{ p, q });
            if (participantIdFromQuery(q)) |uid| {
                var participant: *Participant = undefined;

                // special case: if participant id is 0 -> create new participant
                // and communicate it back!
                if (std.mem.eql(u8, uid, "null")) {
                    std.log.debug("NULL -> newParticipant!!!!", .{});
                    if (self.participants.newParticipant()) |up| {
                        participant = up;
                    } else |err| {
                        std.debug.print("    Error: exhausted number of participants: {d}\n{any}\n", .{ self.max_participants, err });
                        r.setStatus(.internal_server_error);
                        r.sendJson("{ \"status\": \"too many participants\"}") catch return;
                        return;
                    }
                } else {
                    // get the participant
                    if (self.participants.getParticipantFromIdString(uid)) |up| {
                        participant = up;
                    } else |err| {
                        std.debug.print("    Error: invalid participantid {s}\n{any}\n", .{ uid, err });
                        r.setStatus(.internal_server_error);
                        r.sendJson("{ \"status\": \"invalid participant id\"}") catch return;
                        return;
                    }
                }

                // update the participant's appdata based on the received json
                if (r.body) |body| {
                    if (participant.updateAppdataFromJSON(body)) {
                        // OK
                    } else |err| {
                        std.debug.print("    Error cloning appdata: {any}\n", .{err});
                        return;
                    }
                }

                // DEBUG
                var pbuf: [150 * 1024]u8 = undefined;
                var pfba = std.heap.FixedBufferAllocator.init(&pbuf);
                var pstring = std.ArrayList(u8).init(pfba.allocator());
                defer pstring.deinit();
                participant.jsonStringify(.{}, pstring.writer()) catch unreachable;

                if (is_debug_build) {
                    std.debug.print("    participant = {s}\n\n", .{pstring.items});
                }

                if (self.taskIdFromPath(p)) |taskid| {
                    if (self.tasks.json_template.?.value.object.get(taskid)) |*task| {
                        var buf: [50 * 1024]u8 = undefined;
                        var fba = std.heap.FixedBufferAllocator.init(&buf);
                        var string = std.ArrayList(u8).init(fba.allocator());
                        defer string.deinit();
                        // HACK: return list of participantid, task
                        string.writer().print("[ {d}, ", .{participant.participantid}) catch return;
                        if (std.json.stringify(task, .{}, string.writer())) {
                            // close the list of [participantid, task ]
                            string.writer().writeByte(',') catch return;
                            string.writer().writeAll(pstring.items) catch return;
                            string.writer().writeAll("]") catch return;
                            // MUSTACHE THE STRING!!!!
                            const template = string.items;
                            const m = zap.MustacheNew(template) catch return;
                            defer zap.MustacheFree(m);
                            const context = RenderContextFromParticipant(participant);
                            const rendered = zap.MustacheBuild(m, context);
                            defer rendered.deinit();
                            if (rendered.str()) |s| {
                                // std.time.sleep(2 * std.time.ns_per_s);
                                if (is_debug_build) {
                                    std.log.debug("RESPONSE: {s}\n", .{s});
                                }
                                r.sendJson(s) catch return;
                            } else {
                                std.debug.print("    Error\n", .{});
                                r.setStatus(.internal_server_error);
                                r.sendJson("{ \"status\": \"unable to render\"}") catch return;
                            }
                        } else |err| {
                            std.debug.print("    Error: {any}\n", .{err});
                            r.setStatus(.not_found);
                            r.sendJson("{ \"status\": \"not found\"}") catch return;
                        }
                    }
                }
            }
        }
    }
}

fn RenderContextFromParticipant(participant: *Participant) RenderContext {
    return .{
        .participantid = @intCast(participant.participantid),
    };
}

// shouldn't we just return which participant is in which task?
fn listTasks(self: *Self, r: zap.SimpleRequest) void {
    var buf: [100 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var string = std.ArrayList(u8).init(fba.allocator());
    const t = self.tasks.json_template.?.value;
    if (std.json.stringify(t, .{}, string.writer())) {
        r.sendJson(string.items) catch return;
    } else |err| {
        std.debug.print("    /tasks LIST Error: {any}\n", .{err});
        r.setStatus(.not_found);
        r.sendJson("{ \"status\": \"not found\"}") catch return;
    }
}

fn reloadTasks(self: *Self, r: zap.SimpleRequest) void {
    if (self.tasks.update()) {
        r.sendJson("{ \"status\": \"OK\"}") catch return;
    } else |_| {
        r.sendJson("{ \"status\": \"error\"}") catch return;
    }
}

pub fn participantIdFromQuery(query: []const u8) ?[]const u8 {
    var startpos: usize = 0;
    var endpos: usize = query.len;
    if (std.mem.indexOfScalar(u8, query, '&')) |amp| {
        endpos = amp;
    }
    // search for =
    if (std.mem.indexOfScalar(u8, query[startpos..endpos], '=')) |eql| {
        startpos = eql;
    }
    const idstr = query[startpos + 1 .. endpos];
    return idstr;
}
