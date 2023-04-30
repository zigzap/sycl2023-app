const std = @import("std");
const zap = @import("zap");
const Users = @import("../users.zig");
const User = Users.User;

allocator: std.mem.Allocator,
users: *Users = undefined,
endpoint: zap.SimpleEndpoint = undefined,
io_mutex: std.Thread.Mutex = .{},

const Self = @This();

pub fn init(a: std.mem.Allocator, users_path: []const u8, users: *Users) !Self {
    return .{
        .allocator = a,
        .users = users,
        .endpoint = zap.SimpleEndpoint.init(.{
            .path = users_path,
            .get = listUsers,
            .post = null,
            .put = null,
            .delete = null,
        }),
    };
}

pub fn getUsersEndpoint(self: *Self) *zap.SimpleEndpoint {
    return &self.endpoint;
}

// shouldn't we just return which user is in which task?
fn listUsers(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
    const self = @fieldParentPtr(Self, "endpoint", e);

    // if 0 users, reply instantly
    if (self.users.current_user_id == 0) {
        r.sendJson("[]") catch return;
        return;
    }

    var do_save = false;

    if (r.query) |q| {
        if (std.mem.startsWith(u8, q, "save")) {
            do_save = true;
        } else {
            std.debug.print("    unknown query: {s}\n", .{q});
        }
    }
    var buf = self.allocator.alloc(
        u8,
        self.users.current_user_id * 512 * 1024, // 512kb per user
    ) catch return;
    defer self.allocator.free(buf);

    std.debug.print("    Allocated buffer size: {d}kB\n", .{buf.len / 1024});
    var fba = std.heap.FixedBufferAllocator.init(buf);
    var string = std.ArrayList(u8).init(fba.allocator());
    if (self.users.jsonStringify(.{}, string.writer())) {
        if (do_save) {
            std.debug.print("    Saving to users.json...  ", .{});
            if (self.saveUsers(string.items)) {
                std.debug.print("DONE!\n", .{});
            } else |err| {
                std.debug.print("ERROR {any}!\n", .{err});
            }
        }
        r.sendJson(string.items) catch return;
    } else |err| {
        std.debug.print("    /users LIST Error: {any}\n", .{err});
        r.setStatus(.not_found);
        r.sendJson("{ \"status\": \"not found\"}") catch return;
    }
}

fn saveUsers(self: *Self, json: []const u8) !void {
    self.io_mutex.lock();
    defer self.io_mutex.unlock();
    const filn = "users.json";
    var f = try std.fs.cwd().createFile(filn, .{});
    var buffered_writer = std.io.bufferedWriter(f.writer());
    var writer = buffered_writer.writer();
    try writer.writeAll(json);
    try buffered_writer.flush();
    f.close();
}
