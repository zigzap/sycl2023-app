const std = @import("std");
const zap = @import("zap");
const TasksEndpoint = @import("endpoints/tasks_endpoint.zig");
const FrontendEndpoint = @import("endpoints/frontend_endpoint.zig");
const Users = @import("users.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    var allocator = gpa.allocator();

    var users = try Users.init(allocator, 500);
    _ = users;

    zap.Log.fio_set_log_level(zap.Log.fio_log_level_debug);
    std.debug.print(
        \\
        \\
        \\
        \\ ======================================================
        \\ ===   Visit me on http://127.0.0.1:5000/frontend   ===
        \\ ======================================================
        \\
        \\
        \\
    , .{});

    var listener = zap.SimpleEndpointListener.init(allocator, .{
        .port = 5000,
        .on_request = null,
        .max_clients = 100000,
        .log = true,
    });

    // add endpoints
    var tasksEndpoint = try TasksEndpoint.init(allocator, "/sycl-api/tasks");
    var frontendEndpoint = try FrontendEndpoint.init("/frontend");

    try listener.addEndpoint(tasksEndpoint.getTaskEndpoint());
    try listener.addEndpoint(frontendEndpoint.getFrontendEndpoint());

    try listener.listen();
    // start worker threads
    zap.start(.{
        .threads = 4,

        // IMPORTANT! It is crucial to only have a single worker for this example to work!
        // Multiple workers would have multiple copies of the users hashmap.
        //
        // Since zap is quite fast, you can do A LOT with a single worker.
        // Try it with `zig build run-endpoint -Drelease-fast`
        .workers = 1,
    });
    std.debug.print("Threads stopped\n", .{});
}
