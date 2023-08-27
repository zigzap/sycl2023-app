const std = @import("std");
const zap = @import("zap");
const bundledOrLocalDirPathOwned = @import("../maybebundledfile.zig").bundledOrLocalDirPathOwned;
const Self = @This();

allocator: std.mem.Allocator,
endpoint: zap.SimpleEndpoint,
debug: bool = true,
settings: Settings,
frontend_dir_absolute: []const u8,

fn log(self: *Self, comptime fmt: []const u8, args: anytype) void {
    if (self.debug) {
        std.debug.print("[frontend endpoint] - " ++ fmt, args);
    }
}

pub const Settings = struct {
    allocator: std.mem.Allocator,
    endpoint_path: []const u8,
    index_html: []const u8,
};

pub fn init(settings: Settings) !Self {
    // endpoint path = frontend_dir
    if (settings.endpoint_path[0] != '/') {
        return error.FrontendDirMustStartWithSlash;
    }

    var ret: Self = .{
        .allocator = settings.allocator,
        .endpoint = zap.SimpleEndpoint.init(.{
            .path = settings.endpoint_path,
            .get = getFrontend,
            .post = null,
            .put = null,
            .delete = null,
        }),
        .settings = settings,
        .frontend_dir_absolute = undefined,
    };

    // create frontend_dir_absolute for later
    const maybe_relpath = try bundledOrLocalDirPathOwned(ret.allocator, settings.endpoint_path[1..]);
    defer ret.allocator.free(maybe_relpath);
    ret.frontend_dir_absolute = try std.fs.realpathAlloc(ret.allocator, maybe_relpath);

    std.log.info("Frontend: using frontend root: {s}", .{ret.frontend_dir_absolute});
    std.log.info("Frontend: using frontend endpoint: {s}", .{settings.endpoint_path});

    return ret;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.frontend_dir_absolute);
}

pub fn getFrontendEndpoint(self: *Self) *zap.SimpleEndpoint {
    return &self.endpoint;
}

fn getFrontend(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
    const self = @fieldParentPtr(Self, "endpoint", e);
    self.getFrontenInternal(r) catch |err| {
        r.sendError(err, 505);
    };
}

fn getFrontenInternal(self: *Self, r: zap.SimpleRequest) !void {
    var fn_buf: [2048]u8 = undefined;
    _ = fn_buf;
    if (r.path) |p| {
        var html_path: []const u8 = undefined;
        var is_root: bool = false;

        // check if we have to serve index.html
        if (std.mem.eql(u8, p, self.settings.endpoint_path)) {
            html_path = self.settings.index_html;
            is_root = true;
        } else if (p.len == self.settings.endpoint_path.len + 1 and p[p.len - 1] == '/') {
            html_path = self.settings.index_html;
            is_root = true;
        } else {
            // no
            html_path = p;
        }

        // check if request seems valid
        if (std.mem.startsWith(u8, html_path, self.settings.endpoint_path)) {
            // we can safely strip the endpoint path
            // then we make the path absolute and check if it still starts with the endpoint path`
            const endpointless = html_path[self.settings.endpoint_path.len..];
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
            std.debug.print("html path {s} does not start with {s}\n", .{ html_path, self.settings.endpoint_path });
        }
    }

    r.setStatus(.not_found);
    try r.setHeader("Cache-Control", "no-cache");
    try r.sendBody("<html><body><h1>404 - File not found</h1></body></html>");
}
