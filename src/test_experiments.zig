const std = @import("std");
const Experiments = @import("experiments.zig");

const alloc = std.testing.allocator;

test "createExperimentFromFile" {
    // basic test
    var experiments = Experiments.init(alloc);
    var experiment = try experiments.createExperimentFromFile("./data/templates/basic_test.json", false);
    var e = experiment.?.*;
    // defer e.deinit(); - done by experiments

    // now access all elements by printing the experiment
    var buf = try std.fmt.allocPrint(alloc, "{any}\n", .{e});
    defer alloc.free(buf);
    experiments.deinit();
}

test "ExperimentCondition->JSON" {
    const e = Experiments.ExperimentCondition.HumanInfluencer;
    const out = try std.json.stringifyAlloc(alloc, e, .{});
    defer alloc.free(out);
    try std.testing.expectEqualStrings(out, "\"HumanInfluencer\"");
}

test "Users->toJSON" {
    // Create Experiments collection
    var experiments = Experiments.init(alloc);
    defer experiments.deinit();

    // Create one experiment from JSON template file
    var experiment = try experiments.createExperimentFromFile("./data/templates/basic_test.json", false);

    // If we got one:
    // (We might not get one if we request `only_running=true` above)
    if (experiment) |e| {
        // So we got an experiment, now create 3 users that log in:
        var users = e.users;
        _ = try users.newUser();
        _ = try users.newUser();
        _ = try users.newUser();

        // JSONify the users and check if everything went alright
        const out = try std.json.stringifyAlloc(alloc, users, .{});
        defer alloc.free(out);
        try std.testing.expectEqualStrings(out,
            \\[{"userid":0,"current_task_id":"0","appstate":{}},{"userid":1,"current_task_id":"0","appstate":{}},{"userid":2,"current_task_id":"0","appstate":{}}]
        );
    }
}
