const std = @import("std");
const http = @import("http.zig");

const State = enum {
    inited,
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
prepared_response: ?[]const u8 = null,
debug: bool = false,

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
    self.timings.deinit();

    if (self.prepared_response) |pr| {
        self.allocator.free(pr);
    }
}

// - get url/tasks/0
// - post url/tasks/150?userid=null
//    --> [ userid, task ]
//    participant = {"participantid":2,"current_task_id":"0","appstate":{"agreement_checked_at":"2023-05-28 18:17:23.970","dataprotection_checked_at":"2023-05-28 18:17:24.738"}}
// - post url/tasks/userid=n
//    --> [ userid, task ]
pub fn step(self: *Self) !void {
    if (self.debug)
        std.debug.print("STEP: {}\n", .{self.state});
    switch (self.state) {
        .inited => {
            if (self.debug)
                std.debug.print("    sending initial request\n", .{});
            return self.initial_request();
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
        var user_id_str: []const u8 = "null";
        var buf: [256]u8 = undefined;
        if (self.user_id) |uid| {
            user_id_str = try std.fmt.bufPrint(buf[0..], "{d}", .{uid});
        }
        return try std.fmt.allocPrint(
            self.allocator,
            "{s}/tasks/{}?userid={s}",
            .{
                self.server_url,
                task_id,
                user_id_str,
            },
        );
    }
}

const ParseTaskResponseResult = struct {
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

fn parse_response(self: *Self, method: std.http.Method, response_str: []const u8) !ParseTaskResponseResult {
    var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, response_str, .{});

    var task_object: std.json.ObjectMap = undefined;
    var user_id: ?i64 = null;

    switch (method) {
        .GET => {
            switch (parsed.value) {
                .object => |o| {
                    task_object = o;
                },
                else => {
                    return error.ParseError;
                },
            }
        },
        .POST => {
            switch (parsed.value) {
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
    var questions: ?std.json.ObjectMap = null;
    // we have the task object and maybe the user_id
    // parse the task for fields we like
    if (task_object.get("taskbody")) |body| {
        // we assume types from now on
        if (body.object.get("questions")) |qs| {
            questions = qs.object;
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

    var ret: ParseTaskResponseResult = .{
        .user_id = user_id,
        .next_task_id = next_task.?,
        .is_final = is_final,
        .task_type = tasktype.?,
        .questions = questions,
    };
    return ret;
}

pub fn initial_request(self: *Self) !void {
    const url = try self.url_for_task(0);
    defer self.allocator.free(url);
    if (self.debug)
        std.debug.print("    --> {s}\n", .{url});

    var buf = try self.allocator.alloc(u8, 10240);
    defer self.allocator.free(buf);

    const response = try http.get(self.allocator, url, buf);
    const response_str = buf[0..response.length];
    try self.timings.append(response.micoSeconds);

    // initial response is just a task
    const result = try self.parse_response(.GET, response_str);
    self.next_task_id = result.next_task_id;
    if (self.debug)
        std.debug.print("    {any}\n", .{result});
    self.prepared_response = try std.fmt.allocPrint(self.allocator,
        \\{{
        \\     "dataprotection_checked_at" : "now",
        \\     "agreement_checked_at" : "now"
        \\}}
    , .{});
    self.state = .subsequent_requests;
}

const QA = struct {
    question: []const u8,
    answer: []const u8,
};

const QAs = std.ArrayList(QA);

// we're always selecting answer number self.bot_id % answer-options.len
fn select_answers(self: *Self, questions: std.json.ObjectMap, out: *QAs) !void {
    var it = questions.iterator();
    while (it.next()) |entry| {
        const qname = entry.key_ptr.*;
        const qbody = entry.value_ptr.*.object;
        if (qbody.get("options")) |qoptions| {
            const options = qoptions.array.items;
            const seleted_option_index = self.bot_id % options.len;
            const answer = options[seleted_option_index].string;
            const qa: QA = .{
                .question = qname,
                .answer = answer,
            };
            try out.append(qa);
        } else {
            return error.ParseError;
        }
    }
}

pub fn next_post(self: *Self) !void {
    if (self.prepared_response) |post_data| {
        const url = try self.url_for_task(self.next_task_id);
        defer self.allocator.free(url);

        std.debug.print("    --> {s}\n", .{url});

        var buf = try self.allocator.alloc(u8, 10240);
        defer self.allocator.free(buf);

        if (self.debug)
            std.debug.print("\n\n\nSENDING:\n{s}\n\n\n", .{post_data});

        const response = try http.post(self.allocator, url, post_data, buf);
        const response_str = buf[0..response.length];

        if (self.debug)
            std.debug.print("\n\n\nRESPONSE:\n{s}\n\n\n", .{response_str});

        try self.timings.append(response.micoSeconds);

        const result = try self.parse_response(.POST, response_str);
        if (result.user_id) |uid| {
            self.user_id = uid;
        }
        self.next_task_id = result.next_task_id;
        if (self.debug)
            std.debug.print("    {any}\n", .{result});

        self.allocator.free(post_data);

        if (result.questions) |qobject| {
            var qas = QAs.init(self.allocator);
            defer qas.deinit();

            try self.select_answers(qobject, &qas);

            // set self.prepared_response
            var out_buf: [10 * 1024]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&out_buf);
            var string = std.ArrayList(u8).init(fba.allocator());
            var writer = string.writer();
            _ = try writer.writeByte('{');
            for (qas.items, 0..) |item, index| {
                _ = try writer.writeByte('"');
                _ = try writer.write(item.question);
                _ = try writer.write("\":\"");
                _ = try writer.write(item.answer);
                _ = try writer.writeByte('"');
                if (index < qas.items.len - 1) {
                    _ = try writer.writeByte(',');
                }
            }
            _ = try writer.writeByte('}');
            self.prepared_response = try self.allocator.dupe(u8, string.items);
            if (self.debug)
                std.debug.print("\nPREPARED: {s}\n", .{self.prepared_response.?});
        } else {
            self.prepared_response = null;
        }

        if (result.is_final) {
            self.state = .final_request;
        }
    } else {
        return error.StateError;
    }
}

pub fn final_post(self: *Self) !void {
    const url = try self.url_for_task(self.next_task_id);
    defer self.allocator.free(url);

    std.debug.print("    --> {s}\n", .{url});

    var buf = try self.allocator.alloc(u8, 10240);
    defer self.allocator.free(buf);

    const post_data = "{\"finished\": true}";
    if (self.debug)
        std.debug.print("\n\n\nSENDING:\n{s}\n\n\n", .{post_data});

    const response = try http.post(self.allocator, url, post_data, buf);
    const response_str = buf[0..response.length];

    if (self.debug)
        std.debug.print("\n\n\nRESPONSE:\n{s}\n\n\n", .{response_str});

    try self.timings.append(response.micoSeconds);

    // const result = try self.parse_response(.POST, response_str);
    // if (result.user_id) |uid| {
    //     self.user_id = uid;
    // }
    // self.next_task_id = result.next_task_id;
    // std.debug.print("    {any}\n", .{result});

    self.state = .done;
}
