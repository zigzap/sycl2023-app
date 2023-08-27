const std = @import("std");
const zap = @import("zap");
const Participants = @import("../participants.zig");
const Participant = Participants.Participant;
const bundledOrLocalDirPathOwned = @import("../maybebundledfile.zig").bundledOrLocalDirPathOwned;

// we hacked passing in the Authenticator so we can call .logout() on it.
pub fn Endpoint(comptime Authenticator: type) type {
    return struct {
        allocator: std.mem.Allocator,
        participants: *Participants = undefined,
        endpoint: zap.SimpleEndpoint = undefined,
        io_mutex: std.Thread.Mutex = .{},
        authenticator: *Authenticator,
        frontend_dir_absolute: []const u8,

        const Self = @This();

        pub fn init(a: std.mem.Allocator, participants_path: []const u8, participants: *Participants, authenticator: *Authenticator) !Self {
            var ret = Self{
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
                .frontend_dir_absolute = undefined,
            };
            // create frontend_dir_absolute for later
            const maybe_relpath = try bundledOrLocalDirPathOwned(ret.allocator, participants_path[1..]);
            defer ret.allocator.free(maybe_relpath);
            ret.frontend_dir_absolute = try std.fs.realpathAlloc(ret.allocator, maybe_relpath);

            std.log.info("Admin: using admin root: {s}", .{ret.frontend_dir_absolute});
            std.log.info("Admin: using admin endpoint: {s}", .{participants_path});
            return ret;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.frontend_dir_absolute);
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
                var destination: ?[]const u8 = null;

                try r.setHeader("Cache-Control", "no-cache");
                r.setStatus(zap.StatusCode.ok);

                if (std.mem.eql(u8, local_path, "/login")) {
                    destination = "/admin/login.html";
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
                const html_path = destination orelse p;
                std.debug.print("Trying to serve: {s}\n", .{html_path});

                // check if request seems valid
                if (std.mem.startsWith(u8, html_path, self.endpoint.settings.path)) {
                    // we can safely strip the endpoint path
                    // then we make the path absolute and check if it still starts with the endpoint path`
                    const endpointless = html_path[self.endpoint.settings.path.len..];
                    // now append endpointless to absolute endpoint_path
                    const calc_abs_path = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.frontend_dir_absolute, endpointless });
                    defer self.allocator.free(calc_abs_path);
                    const real_calc_abs_path = try std.fs.realpathAlloc(self.allocator, calc_abs_path);
                    defer self.allocator.free(real_calc_abs_path);

                    if (std.mem.startsWith(u8, real_calc_abs_path, self.frontend_dir_absolute)) {
                        try r.setHeader("Cache-Control", "no-cache");
                        try r.sendFile(real_calc_abs_path);
                        return;
                    } // else 404 below
                    else {
                        std.debug.print("html path {s} does not start with {s}\n", .{ real_calc_abs_path, self.frontend_dir_absolute });
                    }
                } else {
                    std.debug.print("html path {s} does not start with {s}\n", .{ html_path, self.endpoint.settings.path });
                }
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
                    std.debug.print("got request to /authenticate!\n", .{});
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
                    if (self.saveParticipants(allocJson.json)) {
                        self.allocator.free(allocJson.buffer_to_free);
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
                try self.countParticipants(r);
            }
            r.setStatus(.not_found);
            r.sendJson("{ \"status\": \"no path\"}") catch return;
        }

        fn countParticipants(self: *Self, r: zap.SimpleRequest) !void {
            const countStats = self.participants.statCounters();

            var buf: [1024]u8 = undefined;
            const json = try std.fmt.bufPrint(&buf,
                \\ {{
                \\    "active": {d},
                \\    "finished" : {d},
                \\    "total" : {}
                \\ }}
            , .{
                countStats.active,
                countStats.finished,
                countStats.total,
            });
            try r.sendJson(json);
        }

        fn saveParticipants(self: *Self, json: []const u8) !void {
            const ts_milli = std.time.milliTimestamp();
            const filn = try std.fmt.allocPrint(self.allocator, "participants.{}.json", .{ts_milli});
            defer self.allocator.free(filn);
            std.debug.print("\n\nSaving to: {s}\n\n", .{filn});
            self.io_mutex.lock();
            defer self.io_mutex.unlock();

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
