const std = @import("std");
const zap = @import("zap");

const Self = @This();

allocator: std.mem.Allocator,
endpoint: zap.SimpleEndpoint,
debug: bool = true,
settings: Settings,
www_root_cage: []const u8,
frontend_dir_absolute: []const u8,

fn log(self: *Self, comptime fmt: []const u8, args: anytype) void {
    if (self.debug) {
        std.debug.print("[frontend endpoint] - " ++ fmt, args);
    }
}

pub const Settings = struct {
    allocator: std.mem.Allocator,
    endpoint_path: []const u8,
    www_root: []const u8,
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
        .www_root_cage = undefined,
    };

    // remember abs path of www_root
    ret.www_root_cage = try std.fs.cwd().realpathAlloc(ret.allocator, settings.www_root);
    std.log.info("Frontend: using www_root: {s}", .{ret.www_root_cage});

    // check for endpoint_path within www_root_cage
    const root_dir = try std.fs.cwd().openDir(ret.www_root_cage, .{});

    // try to find the frontend subdir = endpoint_path without leading /
    const frontend_dir_stat = try root_dir.statFile(settings.endpoint_path[1..]);
    if (!(frontend_dir_stat.kind == .Directory)) {
        return error.NotADirectory;
    }

    // create frontend_dir_absolute for later
    ret.frontend_dir_absolute = try root_dir.realpathAlloc(ret.allocator, settings.endpoint_path[1..]);
    std.log.info("Frontend: using frontend root: {s}", .{ret.frontend_dir_absolute});

    // check if frontend_dir_absolute starts with www_root_absolute
    // to avoid weird linking leading to
    if (!std.mem.startsWith(u8, ret.frontend_dir_absolute, ret.www_root_cage)) {
        return error.FrontendDirNotInRootDir;
    }

    return ret;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.frontend_dir_absolute);
    self.allocator.free(self.www_root_cage);
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

        if (std.fmt.bufPrint(&fn_buf, "{s}{s}", .{ self.www_root_cage, html_path })) |fp| {
            // now check if the absolute path starts with the frontend cage
            if (std.mem.startsWith(u8, fp, self.frontend_dir_absolute)) {
                try r.setHeader("Cache-Control", "no-cache");
                try r.sendFile(fp);
                return;
            } // else 404 below
        } else |err| {
            std.debug.print("Error: {}\n", .{err});
            // continue with 404 below
        }
    }

    r.setStatus(.not_found);
    try r.setHeader("Cache-Control", "no-cache");
    try r.sendBody("<html><body><h1>404 - File not found</h1></body></html>");
}
