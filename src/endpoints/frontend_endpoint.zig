const std = @import("std");
const zap = @import("zap");

const Self = @This();

endpoint: zap.SimpleEndpoint = undefined,
debug: bool = true,

fn log(self: *Self, comptime fmt: []const u8, args: anytype) void {
    if (self.debug) {
        std.debug.print("[frontend endpoint] - " ++ fmt, args);
    }
}

pub fn init(frontend_path: []const u8) !Self {
    return .{
        .endpoint = zap.SimpleEndpoint.init(.{
            .path = frontend_path,
            .get = getFrontend,
            .post = null,
            .put = null,
            .delete = null,
        }),
    };
}

pub fn getFrontendEndpoint(self: *Self) *zap.SimpleEndpoint {
    return &self.endpoint;
}

fn getFrontend(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
    // serve files from /frontend, NO CACHING!

    // const self = @fieldParentPtr(Self, "endpoint", e);

    // log("Frontend entry\n", .{});

    var buf: [512 * 1024]u8 = undefined;
    var fn_buf: [1024]u8 = undefined;
    if (r.path) |p| {
        // log("Frontend path: {s}\n", .{p});
        var html_path: []const u8 = undefined;
        var is_root: bool = false;

        // check if we have to serve index.html
        if (std.mem.eql(u8, p, e.settings.path)) {
            html_path = "/frontend/index.html";
            r.setContentType(.HTML) catch return;
            is_root = true;
        } else if (p.len == e.settings.path.len + 1 and p[p.len - 1] == '/') {
            html_path = "/frontend/index.html";
            r.setContentType(.HTML) catch return;
            is_root = true;
        } else {
            // no
            html_path = p;
        }
        // log("serving {s}\n", .{html_path});
        if (std.fmt.bufPrint(&fn_buf, "./{s}", .{html_path})) |fp| {
            // std.debug.print("FILE: {s}\n", .{fp});
            if (std.fs.cwd().readFile(fp, &buf)) |contents| {
                r.setHeader("Cache-Control", "no-cache") catch return;
                r.setStatus(.ok);
                if (!is_root) {
                    r.setContentTypeFromPath() catch return;
                }
                r.sendBody(contents) catch return;
                return;
            } else |err| {
                std.debug.print("Error: {}\n", .{err});
            }
        } else |err| {
            std.debug.print("Error: {}\n", .{err});
        }
    }

    r.setStatus(.not_found);
    r.setHeader("Cache-Control", "no-cache") catch return;
    r.sendBody("<html><body><h1>404 - File not found</h1></body></html>") catch return;
}
