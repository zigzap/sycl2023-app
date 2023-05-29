const std = @import("std");
const http = @import("http.zig");

const State = enum {
    inited,
    first_request,
    subsequent_requests,
    final_request,
    done,
};

allocator: std.mem.Allocator,
bot_id: usize,
server_url: []const u8,
state: State,
user_id: ?i64 = null,
next_task_id: i64 = 0,
timings: std.ArrayList(i64),

const Self = @This();

pub fn init(alloc: std.mem.Allocator, bot_id: usize, server_url: []const u8) Self {
    return .{
        .allocator = alloc,
        .bot_id = bot_id,
        .server_url = server_url,
        .state = .inited,
        .timings = std.ArrayList(i64).init(alloc),
    };
}

pub fn deinit(self: *Self) void {
    std.debug.print("\n\nRESPONSE TIMINGS:\n", .{});
    for (self.timings.items) |i| {
        std.debug.print("    {}us\n", .{i});
    }
}

// - get url/tasks/0
// - post url/tasks/150?userid=null
//    --> [ userid, task ]
//    participant = {"participantid":2,"current_task_id":"0","appstate":{"agreement_checked_at":"2023-05-28 18:17:23.970","dataprotection_checked_at":"2023-05-28 18:17:24.738"}}
// - post url/tasks/userid=n
//    --> [ userid, task ]
pub fn step(self: *Self) !void {
    std.debug.print("STEP: {}\n", .{self.state});
    switch (self.state) {
        .inited => {
            std.debug.print("    sending initial request\n", .{});
            return self.initial_request();
        },
        .first_request => {
            return self.first_post();
        },
        .subsequent_requests => {
            return self.next_post();
        },
        .final_request => {
            // not sure if it is necessary to have this final_request enum value
            return self.final_post();
        },
        .done => {
            return error.AlreadyFinished;
        },
    }
}

fn url_for_task(self: *const Self, task_id: i64) ![]const u8 {
    if (task_id == 0) {
        return try std.fmt.allocPrint(
            self.allocator,
            "{s}/tasks/{}?userid=null",
            .{
                self.server_url,
                task_id,
            },
        );
    } else {
        return try std.fmt.allocPrint(
            self.allocator,
            "{s}/tasks/{}",
            .{
                self.server_url,
                task_id,
            },
        );
    }
}

const ParseTaskResponse = struct {
    next_task_id: i64,
    is_final: bool,
    user_id: ?i64 = null,
    questions: ?std.json.ObjectMap = null,
    task_type: []const u8,
};

fn stringify(something: anytype) !void {
    var writer = std.io.getStdOut().writer();
    try std.json.stringify(something, .{}, writer);
}

fn parse_response(self: *Self, method: std.http.Method, response_str: []const u8) !ParseTaskResponse {
    var parser = std.json.Parser.init(self.allocator, .alloc_always);
    const valueTree = try parser.parse(response_str);

    var task_object: std.json.ObjectMap = undefined;
    var user_id: ?i64 = null;

    switch (method) {
        .GET => {
            switch (valueTree.root) {
                .object => |o| {
                    task_object = o;
                },
                else => {
                    return error.ParseError;
                },
            }
        },
        .POST => {
            switch (valueTree.root) {
                .array => |arr| {
                    if (arr.items.len != 2) return error.ParseError;
                    const maybe_userid = arr.items[0];
                    switch (maybe_userid) {
                        .integer => |i| {
                            user_id = i;
                        },
                        else => {
                            return error.ParseError;
                        },
                    }

                    const maybe_task = arr.items[1];
                    switch (maybe_task) {
                        .object => |o| {
                            task_object = o;
                        },
                        else => {
                            return error.ParseError;
                        },
                    }
                },
                else => {
                    return error.ParseError;
                },
            }
        },
        else => {
            return error.InvalidRequestMethod;
        },
    }

    var next_task: ?i64 = null;
    var is_final: bool = false;
    var tasktype: ?[]const u8 = null;

    // we have the task object and maybe the user_id
    // parse the task for fields we like
    if (task_object.get("taskbody")) |body| {
        // we assume types from now on
        if (body.object.get("questions")) |questions| {
            // iterate through all of them.
            var it = questions.object.iterator();
            while (it.next()) |entry| {
                const q_name = entry.key_ptr;
                _ = q_name;
                const options = entry.value_ptr;
                _ = options;
            }
        }
    }

    if (task_object.get("tasktype")) |ttype| {
        tasktype = ttype.string;
    } else {
        return error.ParseError;
    }

    if (task_object.get("next_task")) |n_task| {
        next_task = n_task.integer;
    } else {
        return error.ParseError;
    }

    if (task_object.get("final_task")) |final| {
        is_final = final.bool;
    }

    var ret: ParseTaskResponse = .{
        .user_id = user_id,
        .next_task_id = next_task.?,
        .is_final = is_final,
        .task_type = tasktype.?,
    };
    return ret;
}

pub fn initial_request(self: *Self) !void {
    const url = try self.url_for_task(0);
    defer self.allocator.free(url);
    std.debug.print("    --> {s}\n", .{url});
    var buf = try self.allocator.alloc(u8, 10240);
    defer self.allocator.free(buf);
    const get_response = try http.get(self.allocator, url, buf);
    const response_str = buf[0..get_response.length];
    try self.timings.append(get_response.micoSeconds);

    // initial response is just a task
    const response = try self.parse_response(.GET, response_str);
    self.next_task_id = response.next_task_id;
    std.debug.print("    {any}\n", .{response});
}

pub fn first_post(self: *Self) !void {
    _ = self;
    //
}

pub fn next_post(self: *Self) !void {
    _ = self;
    //
}

pub fn final_post(self: *Self) !void {
    _ = self;
    //
}
