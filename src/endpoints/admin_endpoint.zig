const std = @import("std");
const zap = @import("zap");
const Participants = @import("../participants.zig");
const Participant = Participants.Participant;

// we hacked passing in the Authenticator so we can call .logout() on it.
pub fn Endpoint(comptime Authenticator: type) type {
    return struct {
        allocator: std.mem.Allocator,
        participants: *Participants = undefined,
        endpoint: zap.SimpleEndpoint = undefined,
        io_mutex: std.Thread.Mutex = .{},
        authenticator: *Authenticator,

        const Self = @This();

        pub fn init(a: std.mem.Allocator, participants_path: []const u8, participants: *Participants, authenticator: *Authenticator) !Self {
            return .{
                .allocator = a,
                .participants = participants,
                .endpoint = zap.SimpleEndpoint.init(.{
                    .path = participants_path,
                    .get = get,
                    .post = post,
                    .put = null,
                    .delete = null,
                    .unauthorized = unauthorized,
                }),
                .authenticator = authenticator,
            };
        }

        pub fn getAdminEndpoint(self: *Self) *zap.SimpleEndpoint {
            return &self.endpoint;
        }

        fn unauthorized(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
            std.debug.print("\n\n\n/admin/unauthorized()\n\n", .{});
            const self = @fieldParentPtr(Self, "endpoint", e);
            self.authenticator.*.authenticator.logout(&r);
        }

        fn get(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
            const self = @fieldParentPtr(Self, "endpoint", e);
            self.getInternal(r) catch |err| {
                r.sendError(err, 505);
            };
        }

        fn getInternal(self: *Self, r: zap.SimpleRequest) !void {
            if (r.path) |p| {
                const local_path = p[6..];

                try r.setHeader("Cache-Control", "no-cache");

                if (std.mem.eql(u8, local_path, "/login")) {
                    try r.sendFile("admin/login.html");
                }

                if (std.mem.eql(u8, local_path, "/logout")) {
                    self.authenticator.*.authenticator.logout(&r);
                    std.debug.print("\n\nLOgged OUT!!!\n\n", .{});
                    try r.redirectTo("/admin/login", .found);
                    return;
                }

                if (std.mem.eql(u8, local_path, "/save")) {
                    return listOrSaveParticipants(self, r, local_path);
                }

                if (std.mem.eql(u8, local_path, "/list")) {
                    return listOrSaveParticipants(self, r, local_path);
                }

                if (std.mem.eql(u8, local_path, "/count")) {
                    return listOrSaveParticipants(self, r, local_path);
                }

                // ELSE serve file
                const file_path = p[1..];
                std.debug.print("Trying to serve: {s}\n", .{file_path});
                try r.sendFile(file_path);
            }
        }

        fn post(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
            const self = @fieldParentPtr(Self, "endpoint", e);
            self.postInternal(r) catch |err| {
                r.sendError(err, 505);
            };
        }

        fn postInternal(self: *Self, r: zap.SimpleRequest) !void {
            _ = self;
            if (r.path) |p| {
                const local_path = p[6..];

                if (std.mem.eql(u8, local_path, "/authenticate")) {
                    try r.redirectTo("/admin/index.html", .found);
                }

                // ELSE serve file
                const file_path = p[1..];
                std.debug.print("Trying to serve: {s}\n", .{file_path});
                try r.sendBody("WTF");
            }
        }

        fn listOrSaveParticipants(self: *Self, r: zap.SimpleRequest, local_path: []const u8) !void {
            const path = local_path;
            if (std.mem.endsWith(u8, path, "/save")) {
                if (self.participantsToJsonAlloc()) |allocJson| {
                    std.debug.print("    Saving to participants.json...  ", .{});
                    if (self.saveParticipants(allocJson.json)) {
                        self.allocator.free(allocJson.buffer_to_free);
                        std.debug.print("DONE!\n", .{});
                        var buf: [128]u8 = undefined;
                        const x = try std.fmt.bufPrint(&buf, "{{ \"status\": \"OK\", \"SAVED\": {} }}", .{self.participants.current_participant_id});
                        r.sendJson(x) catch return;
                    } else |err| {
                        std.debug.print("ERROR {any}!\n", .{err});
                        r.sendJson("{ \"error\": \"not saved\"}") catch return;
                    }
                } else |err| {
                    // TODO: what's the best status to return?
                    std.debug.print("    save error: {any}\n", .{err});
                    r.setStatus(.not_found);
                    r.sendJson("{ \"status\": \"not found\"}") catch return;
                }
            } else if (std.mem.endsWith(u8, path, "/list")) {
                if (self.participantsToJsonAlloc()) |allocJson| {
                    defer self.allocator.free(allocJson.buffer_to_free);
                    r.sendJson(allocJson.json) catch return;
                } else |err| {
                    // TODO: what's the best status to return?
                    std.debug.print("    list error: {any}\n", .{err});
                    r.setStatus(.not_found);
                    r.sendJson("{ \"status\": \"not found\"}") catch return;
                }
            } else if (std.mem.endsWith(u8, path, "/count")) {
                var buf: [128]u8 = undefined;
                if (std.fmt.bufPrint(&buf,
                    \\ {{
                    \\    "count" : {d}
                    \\ }}
                , .{self.participants.current_participant_id})) |json| {
                    r.sendJson(json) catch return;
                } else |err| {
                    std.debug.print("    count error: {any}\n", .{err});
                    r.setStatus(.not_found);
                    r.sendJson("{ \"status\": \"not found\"}") catch return;
                }
            }
            r.setStatus(.not_found);
            r.sendJson("{ \"status\": \"no path\"}") catch return;
        }

        fn saveParticipants(self: *Self, json: []const u8) !void {
            self.io_mutex.lock();
            defer self.io_mutex.unlock();
            const filn = "participants.json";
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

        fn participantsToJsonAlloc(self: *Self) !AllocJson {
            std.debug.print("\n\n/save: {} participants\n\n", .{self.participants.current_participant_id});
            if (self.participants.current_participant_id == 0) {
                var json = try std.fmt.allocPrint(self.allocator, "{{}}", .{});

                return .{
                    .json = json,
                    .buffer_to_free = json,
                };
            }

            var buf = try self.allocator.alloc(
                u8,
                self.participants.current_participant_id * 512 * 1024, // 512kb per participant
            );
            errdefer self.allocator.free(buf);

            std.debug.print("    Allocated buffer size: {d}kB for {d} participants.\n", .{ buf.len / 1024, self.participants.current_participant_id });
            var fba = std.heap.FixedBufferAllocator.init(buf);
            var string = std.ArrayList(u8).init(fba.allocator());
            if (self.participants.jsonStringify(.{}, string.writer())) {
                return .{
                    .json = string.items,
                    .buffer_to_free = buf,
                };
            } else |err| {
                return err;
            }
        }
    };
}
