const std = @import("std");
const zap = @import("zap");
const Tasks = @import("../tasks.zig");
const Users = @import("../users.zig");
const User = Users.User;

alloc: std.mem.Allocator = undefined,
endpoint: zap.SimpleEndpoint = undefined,
users: Users = undefined,
tasks: Tasks = undefined,
max_users: usize,

pub const Self = @This();

// not using context / callback functions from mustache. we rather use prepared vars
pub const RenderContext = struct {
    // put stuff in there you want to refer in the json template
    userid: isize,
    rustOrBust: bool,
};

pub fn init(
    a: std.mem.Allocator,
    task_path: []const u8,
    task_template_filn: []const u8,
    max_users: usize,
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
        .users = try Users.init(a, max_users),
        .max_users = max_users,
    };
    return ret;
}

pub fn getUsers(self: *Self) *Users {
    return &self.users;
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

        // get userid from query
        if (r.query) |q| {
            if (userIdFromQuery(q)) |uid| {
                if (!std.mem.eql(u8, uid, "null")) {
                    std.debug.print("    ERROR User ID must be null, got: {s}\n", .{uid});
                    r.sendJson("{\"error\": \"invalid user id\"}") catch return;
                    return;
                }
                if (self.taskIdFromPath(p)) |taskid| {
                    if (self.tasks.json_template.?.root.object.get(taskid)) |*task| {
                        // task.dump();
                        var buf: [100 * 1024]u8 = undefined;
                        var fba = std.heap.FixedBufferAllocator.init(&buf);
                        var string = std.ArrayList(u8).init(fba.allocator());
                        if (task.jsonStringify(.{}, string.writer())) {
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
                    }
                }
            }
        }
    }
}

fn postTask(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
    const self = @fieldParentPtr(Self, "endpoint", e);
    if (r.path) |p| {
        // get userid from query
        if (r.query) |q| {
            std.debug.print("    post {s}?{s}\n", .{ p, q });
            if (userIdFromQuery(q)) |uid| {
                var user: *User = undefined;

                // special case: if user id is 0 -> create new user and
                // communicate it back!
                if (std.mem.eql(u8, uid, "null")) {
                    if (self.users.newUser()) |up| {
                        user = up;
                    } else |err| {
                        std.debug.print("    Error: exhausted number of users: {d}\n{any}\n", .{ self.max_users, err });
                        r.setStatus(.internal_server_error);
                        r.sendJson("{ \"status\": \"too many users\"}") catch return;
                        return;
                    }
                } else {
                    // get the user
                    if (self.users.getUserFromIdString(uid)) |up| {
                        user = up;
                    } else |err| {
                        std.debug.print("    Error: invalid userid {s}\n{any}\n", .{ uid, err });
                        r.setStatus(.internal_server_error);
                        r.sendJson("{ \"status\": \"invalid user id\"}") catch return;
                        return;
                    }
                }

                // update the user's appdata based on the received json
                if (r.body) |body| {
                    if (user.updateAppdataFromJSON(body)) {
                        // OK
                    } else |err| {
                        std.debug.print("    Error cloning appdata: {any}\n", .{err});
                        return;
                    }
                    // DEBUG
                    var buf: [100 * 1024]u8 = undefined;
                    var fba = std.heap.FixedBufferAllocator.init(&buf);
                    var string = std.ArrayList(u8).init(fba.allocator());
                    user.jsonStringify(.{}, string.writer()) catch unreachable;
                    std.debug.print("    user = {s}\n\n", .{string.items});
                }
                if (self.taskIdFromPath(p)) |taskid| {
                    if (self.tasks.json_template.?.root.object.get(taskid)) |*task| {
                        var buf: [100 * 1024]u8 = undefined;
                        var fba = std.heap.FixedBufferAllocator.init(&buf);
                        var string = std.ArrayList(u8).init(fba.allocator());
                        // HACK: return list of userid, task
                        string.writer().print("[ {d}, ", .{user.userid}) catch return;
                        if (task.jsonStringify(.{}, string.writer())) {
                            // close the list of [userid, task ]
                            string.writer().writeAll("]") catch return;
                            // MUSTACHE THE STRING!!!!
                            const template = string.items;
                            const m = zap.MustacheNew(template) catch return;
                            defer zap.MustacheFree(m);
                            const context = RenderContextFromUser(user);
                            const rendered = zap.MustacheBuild(m, context);
                            defer rendered.deinit();
                            if (rendered.str()) |s| {
                                // std.time.sleep(2 * std.time.ns_per_s);
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

fn RenderContextFromUser(user: *User) RenderContext {
    return .{
        .userid = @intCast(isize, user.userid),
        .rustOrBust = false,
    };
}

// shouldn't we just return which user is in which task?
fn listTasks(self: *Self, r: zap.SimpleRequest) void {
    var buf: [100 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var string = std.ArrayList(u8).init(fba.allocator());
    const t = self.tasks.json_template.?.root;
    if (t.jsonStringify(.{}, string.writer())) {
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

pub fn userIdFromQuery(query: []const u8) ?[]const u8 {
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
