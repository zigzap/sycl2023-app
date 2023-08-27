const std = @import("std");
const zap = @import("zap");
const TasksEndpoint = @import("endpoints/tasks_endpoint.zig");
const FrontendEndpoint = @import("endpoints/frontend_endpoint.zig");
const AdminEndpoint = @import("endpoints/admin_endpoint.zig");
const PWAuthenticator = @import("pwauth.zig");
const bundledOrLocalFilePathOwned = @import("maybebundledfile.zig").bundledOrLocalFilePathOwned;

const survey_tasks_template = "data/templates/sycl2023-survey.json";

// max size for all persisted participants when reading the file
const participants_json_maxsize = 50 * 1024 * 1024;
const participants_json_filn = "participants.json";

const FRONTEND_SLUG = "/frontend";
const ADMIN_SLUG = "/admin";

// go to /frontend per default
fn on_default_request(r: zap.SimpleRequest) void {
    const redirect_target = FRONTEND_SLUG ++ "/";
    r.redirectTo(redirect_target, .found) catch |err| {
        std.log.err("could not redirect to {s}: {any}\n", .{ redirect_target, err });
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    var allocator = gpa.allocator();

    zap.Log.fio_set_log_level(zap.Log.fio_log_level_debug);
    std.debug.print(
        \\
        \\
        \\
        \\ ======================================================
        \\ ===   Visit me on http://127.0.0.1:5000{s}   ===
        \\ ======================================================
        \\
        \\
        \\
    , .{FRONTEND_SLUG});

    var listener = zap.SimpleEndpointListener.init(allocator, .{
        .port = 5000,
        .on_request = on_default_request,
        .max_clients = 100000,
        .log = true,
    });

    // /sycl-api/tasks
    //
    // Serves a JSON API
    //
    // The tasks API endpoint. Will be queried by the frontends running in the
    // browsers of participants
    //
    var tasksEndpoint = blk: {
        if (TasksEndpoint.init(
            allocator,
            "/sycl-api/tasks", // slug
            survey_tasks_template, // task template
            10000, // max. 1000 participants
        )) |ep| {
            break :blk ep;
        } else |err| {
            switch (err) {
                error.FileNotFound => |e| std.debug.print("File not found: {any}\n", .{e}),
                else => |e| {
                    std.debug.print("File parsing error: {any}\n", .{e});
                    return e;
                },
            }
            return;
        }
    };
    defer tasksEndpoint.deinit();

    // /frontend
    //
    // Serves HTML
    //
    // The Questionnaire SPA running in the browser will fetch its files from
    // here.
    //
    var frontendEndpoint = try FrontendEndpoint.init(.{
        .allocator = allocator,
        .endpoint_path = FRONTEND_SLUG,
        .index_html = FRONTEND_SLUG ++ "/index.html",
    });

    //
    // /admin
    //
    // Serves the admin frontend plus the admin JSON API.
    //
    // This used to be an API for participants. For the sake of simplicity, we'll pivot
    // to it being the "admin" webapp. It's protected by username / pw auth
    // and let you display statistics, download JSON, etc.

    // first, create the UserPassword Authenticator from the passwords file
    const pw_filn = "passwords.txt";
    const pw_filp = try bundledOrLocalFilePathOwned(allocator, pw_filn);
    defer allocator.free(pw_filp);
    var pw_authenticator = PWAuthenticator.init(
        allocator,
        pw_filp,
        ADMIN_SLUG ++ "/login",
    ) catch |err| {
        std.debug.print(
            "ERROR: Could not read {s}: {any}\n",
            .{ pw_filp, err },
        );
        return;
    };
    defer pw_authenticator.deinit();

    var participants = tasksEndpoint.getParticipants(); // the admin endpoint needs access to the participants
    // we hacked passing in the PWAuthenticator so we can call .logout() on it.
    var adminEndpoint = try AdminEndpoint.Endpoint(PWAuthenticator).init(
        allocator,
        ADMIN_SLUG,
        participants,
        &pw_authenticator,
    );

    // We wrap the admin endpoint that does the actual work in the PW authenticator
    const PWAuthenticatingEndpoint = zap.AuthenticatingEndpoint(PWAuthenticator.Authenticator);
    var pwauthAdminEndpoint = PWAuthenticatingEndpoint.init(adminEndpoint.getAdminEndpoint(), &pw_authenticator.authenticator);

    // If specified on the command line, we load a previously saved participants state on startup
    var args = std.process.args();
    // TODO: change that to: load file if ends in .json, else if "reload-latest":
    // list, sort, pick latest, reload
    var do_load = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "reload")) {
            do_load = true;
        }
    }

    // check if we have a participants.json - and load
    if (do_load) {
        var dir = std.fs.cwd();
        if (dir.statFile(participants_json_filn)) |_| {
            std.debug.print("\n\nL O A D I N G   E X I S T I N G   " ++ participants_json_filn ++ "\n", .{});
            const template_buf = try std.fs.cwd().readFileAlloc(allocator, participants_json_filn, participants_json_maxsize);
            defer allocator.free(template_buf);
            if (template_buf.len > 0) {
                try participants.restoreStateFromJson(template_buf);
            }
        } else |err| {
            std.debug.print("ERROR loading " ++ participants_json_filn ++ ": {any}\n", .{err});
        }
    }

    // add all endpoints to the listener
    try listener.addEndpoint(tasksEndpoint.getTaskEndpoint());
    try listener.addEndpoint(frontendEndpoint.getFrontendEndpoint());
    try listener.addEndpoint(pwauthAdminEndpoint.getEndpoint());

    // and GO!
    try listener.listen();
    zap.enableDebugLog();

    // start worker threads
    zap.start(.{
        .threads = 4,

        // IMPORTANT!
        //
        // It is crucial to only have a single worker for this example to work!
        // Multiple workers would have multiple copies of the participants hashmap.
        //
        // Since zap is quite fast, you can do A LOT with a single worker.
        // Try it with `zig build -Doptimize=ReleaseFast
        .workers = 1,
    });
    std.debug.print("\n\nThreads stopped\n", .{});
}
