const std = @import("std");
const zap = @import("zap");

fn on_request(r: zap.SimpleRequest) void {
    var buf: [512 * 1024]u8 = undefined;
    var fn_buf: [1024]u8 = undefined;

    // serve files from /frontend, NO CACHING!
    if (r.path) |p| {
        var html_path: []const u8 = undefined;
        var is_root: bool = false;
        if (p.len == 1 and p[0] == '/') {
            html_path = "/index.html";
            r.setContentType(.HTML) catch return;
            is_root = true;
        } else {
            html_path = p;
        }
        if (std.fmt.bufPrint(&fn_buf, "./frontend{s}", .{html_path})) |fp| {
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

pub fn main() !void {
    var listener = zap.SimpleHttpListener.init(.{
        .port = 3000,
        .on_request = on_request,
        // .public_folder = std.mem.span("frontend"),
        .log = true,
    });
    try listener.listen();

    std.debug.print("\nDev Server is listening on 0.0.0.0:3000\n", .{});

    // start worker threads
    zap.start(.{
        .threads = 20,
        .workers = 1,
    });
    std.debug.print("Dev Server has stopped\n", .{});
}
