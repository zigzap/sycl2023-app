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
            .get = listOrSaveUsers,
            .post = null,
            .put = null,
            .delete = null,
            .unauthorized = unauthorized,
        }),
    };
}

pub fn getUsersEndpoint(self: *Self) *zap.SimpleEndpoint {
    return &self.endpoint;
}

fn unauthorized(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
    _ = r;
    _ = e;
    std.debug.print("UNAUTHORIZED\n", .{});
}

fn listOrSaveUsers(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
    const self = @fieldParentPtr(Self, "endpoint", e);

    if (r.path) |path| {
        if (std.mem.endsWith(u8, path, "/save")) {
            if (self.usersToJsonAlloc()) |allocJson| {
                std.debug.print("    Saving to users.json...  ", .{});
                if (self.saveUsers(allocJson.json)) {
                    self.allocator.free(allocJson.buffer_to_free);
                    std.debug.print("DONE!\n", .{});
                    r.sendJson("{ \"status\": \"OK\"}") catch return;
                } else |err| {
                    std.debug.print("ERROR {any}!\n", .{err});
                    r.sendJson("{ \"error\": \"not saved\"}") catch return;
                }
            } else |err| {
                // TODO: what's the best status to return?
                std.debug.print("    /users/save error: {any}\n", .{err});
                r.setStatus(.not_found);
                r.sendJson("{ \"status\": \"not found\"}") catch return;
            }
        } else if (std.mem.endsWith(u8, path, "/list")) {
            if (self.usersToJsonAlloc()) |allocJson| {
                defer self.allocator.free(allocJson.buffer_to_free);
                r.sendJson(allocJson.json) catch return;
            } else |err| {
                // TODO: what's the best status to return?
                std.debug.print("    /users/list error: {any}\n", .{err});
                r.setStatus(.not_found);
                r.sendJson("{ \"status\": \"not found\"}") catch return;
            }
        }
    }
    r.setStatus(.not_found);
    r.sendJson("{ \"status\": \"no path\"}") catch return;
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

const AllocJson = struct {
    json: []const u8,
    buffer_to_free: []u8,
};

fn usersToJsonAlloc(self: *Self) !AllocJson {
    var buf = try self.allocator.alloc(
        u8,
        self.users.current_user_id * 512 * 1024, // 512kb per user
    );
    errdefer self.allocator.free(buf);

    std.debug.print("    Allocated buffer size: {d}kB for {d} users.\n", .{ buf.len / 1024, self.users.current_user_id });
    var fba = std.heap.FixedBufferAllocator.init(buf);
    var string = std.ArrayList(u8).init(fba.allocator());
    if (self.users.jsonStringify(.{}, string.writer())) {
        return .{
            .json = string.items,
            .buffer_to_free = buf,
        };
    } else |err| {
        return err;
    }
}
