const std = @import("std");
const zap = @import("zap");
const TasksEndpoint = @import("endpoints/tasks_endpoint.zig");
const FrontendEndpoint = @import("endpoints/frontend_endpoint.zig");
const UsersEndpoint = @import("endpoints/users_endpoint.zig");
const PWAuthenticator = @import("pwauth.zig");

const survey_tasks_template = "data/templates/sycl2023-survey.json";
const users_json_maxsize = 1024 * 50;
const users_json_filn = "users.json";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    var allocator = gpa.allocator();

    // first, create the UserPassword Authenticator from the passwords file
    const pw_filn = "passwords.txt";
    var pw_authenticator = PWAuthenticator.init(
        allocator,
        pw_filn,
        "/login",
    ) catch |err| {
        std.debug.print(
            "ERROR: Could not read " ++ pw_filn ++ ": {any}\n",
            .{err},
        );
        return;
    };
    defer pw_authenticator.deinit();

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

    //
    // /SYCL-API/TASKS
    //
    // The tasks endpoint. Will be queried by the frontends running in the
    // browsers of participants
    //
    var tasksEndpoint = blk: {
        if (TasksEndpoint.init(
            allocator,
            "/sycl-api/tasks", // slug
            survey_tasks_template, // task template
            1000, // max. 1000 users
        )) |ep| {
            break :blk ep;
        } else |err| {
            switch (err) {
                error.FileNotFound => |e| std.debug.print("File not found: {any}\n", .{e}),
                else => |e| std.debug.print("File parsing error: {any}\n", .{e}),
            }
            return;
        }
    };

    //
    // /FRONTEND
    //
    // The Questionnaire SPA running in the browser will fetch its files from
    // here.
    //
    var frontendEndpoint = try FrontendEndpoint.init(.{
        .allocator = allocator,
        .www_root = ".",
        .endpoint_path = "/frontend",
        .index_html = "/frontend/index.html",
    });

    //
    // /admin
    //
    // This used to be an API for users. For the sake of simplicity, we'll pivot
    // to it being the "admin" webapp. It's protected by username / pw auth
    // and let you display statistics, download JSON, etc.
    //
    var users = tasksEndpoint.getUsers();
    var usersEndpoint = try UsersEndpoint.init(
        allocator,
        "/admin",
        tasksEndpoint.getUsers(),
    );
    const PWAuthenticatingEndpoint = zap.AuthenticatingEndpoint(PWAuthenticator.Authenticator);
    var pw_auth_endpoint = PWAuthenticatingEndpoint.init(usersEndpoint.getUsersEndpoint(), &pw_authenticator.authenticator);

    var args = std.process.args();
    var do_load = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "reload")) {
            do_load = true;
        }
    }
    // check if we have a users.json
    if (do_load) {
        var dir = std.fs.cwd();
        if (dir.statFile(users_json_filn)) |_| {
            std.debug.print("\n\nL O A D I N G   E X I S T I N G   " ++ users_json_filn ++ "\n", .{});
            const template_buf = try std.fs.cwd().readFileAlloc(allocator, users_json_filn, users_json_maxsize);
            defer allocator.free(template_buf);
            if (template_buf.len > 0) {
                try users.restoreStateFromJson(template_buf);
            }
        } else |err| {
            std.debug.print("ERROR loading " ++ users_json_filn ++ ": {any}\n", .{err});
        }
    }

    try listener.addEndpoint(tasksEndpoint.getTaskEndpoint());
    try listener.addEndpoint(frontendEndpoint.getFrontendEndpoint());
    try listener.addEndpoint(pw_auth_endpoint.getEndpoint());

    try listener.listen();
    zap.enableDebugLog();
    // start worker threads
    zap.start(.{
        .threads = 4,

        // IMPORTANT!
        //
        // It is crucial to only have a single worker for this example to work!
        // Multiple workers would have multiple copies of the users hashmap.
        //
        // Since zap is quite fast, you can do A LOT with a single worker.
        // Try it with `zig build -Doptimize=ReleaseFast
        .workers = 1,
    });
    std.debug.print("\n\nThreads stopped\n", .{});
}
