const std = @import("std");
const zap = @import("zap");
const Tasks = @import("../tasks.zig");
const Users = @import("../users.zig");
const Experiments = @import("../experiments.zig");
const userIdFromQuery = @import("../common.zig").userIdFromQuery;

alloc: std.mem.Allocator = undefined,
endpoint: zap.SimpleEndpoint = undefined,
dummy_users: Users = undefined,
dummy_user: *Users.User = undefined,
tasks: Tasks = undefined,

pub const Self = @This();

// not using context / callback functions from mustache. we rather use prepared vars
pub const RenderContext = struct {
    experiment_condition: Experiments.ExperimentCondition,
    textonly: bool,
    spent_budget: f32,
    payout: f32,
    performance_based_payout: f32,
    has_bonus_payment: bool,
    bonus_payment_amount: f32,
    did_not_spend: bool,
    /// formatted floats
    payout_fmt: *const [5:0]u8,
    performance_based_payout_fmt: *const [5:0]u8,
    bonus_payment_amount_fmt: *const [5:0]u8,
};

pub fn init(
    a: std.mem.Allocator,
    task_path: []const u8,
) !Self {
    var ret: Self = .{
        .tasks = try Tasks.init(a),
        .alloc = a,
        .endpoint = zap.SimpleEndpoint.init(.{
            .path = task_path,
            .get = getTask,
            .post = null,
            .put = null,
            .delete = null,
        }),
        .dummy_users = try Users.init(a, 10),
    };
    ret.dummy_user = try ret.dummy_users.newUser();
    return ret;
}

pub fn getTasks(self: *Self) *Tasks {
    return &self.tasks;
}

pub fn getTaskEndpoint(self: *Self) *zap.SimpleEndpoint {
    return &self.endpoint;
}

fn taskIdFromPath(self: *Self, path: []const u8) ?[]const u8 {
    if (path.len >= self.endpoint.settings.path.len + 2) {
        if (path[self.endpoint.settings.path.len] != '/') {
            return null;
        }
        const idstr = path[self.endpoint.settings.path.len + 1 ..];
        return idstr;
    }
    return null;
}

// get user
// get task
// TODO : mustache it
pub fn renderUserTask(self: *Self, userid: usize, writer: anytype) !void {
    _ = self;
    _ = userid;
    _ = writer;
}

fn getTask(e: *zap.SimpleEndpoint, r: zap.SimpleRequest) void {
    const self = @fieldParentPtr(Self, "endpoint", e);
    if (r.path) |p| {
        // /tasks
        if (p.len == e.settings.path.len) {
            return self.listTasks(r);
        }

        // get userid from query
        if (r.query) |q| {
            if (userIdFromQuery(q)) |uid| {
                if (!std.mem.eql(u8, uid, "1")) {
                    std.debug.print("ERROR User ID: {s}\n", .{uid});
                    r.sendJson("{\"error\": \"invalid user id\"}") catch return;
                    return;
                }
                if (self.taskIdFromPath(p)) |taskid| {
                    if (self.tasks.json_template.root.Object.get(taskid)) |*t| {
                        // t.dump();
                        var buf: [100 * 1024]u8 = undefined;
                        var fba = std.heap.FixedBufferAllocator.init(&buf);
                        var string = std.ArrayList(u8).init(fba.allocator());
                        if (t.jsonStringify(.{}, string.writer())) {

                            // MUSTACHE THE STRING!!!!
                            const template = string.items;
                            const m = zap.MustacheNew(template) catch return;
                            defer zap.MustacheFree(m);
                            const context: RenderContext = .{
                                .experiment_condition = Experiments.ExperimentCondition.HumanInfluencer,
                                .textonly = false,
                                .spent_budget = 10.0,
                                .payout = 3.4,
                                .payout_fmt = " 3.40",
                                .performance_based_payout = 1.4,
                                .has_bonus_payment = true,
                                .bonus_payment_amount = 1.4,
                                .did_not_spend = false,
                                .performance_based_payout_fmt = " 1.40",
                                .bonus_payment_amount_fmt = " 0.40",
                            };
                            const rendered = zap.MustacheBuild(m, context);
                            defer rendered.deinit();
                            if (rendered.str()) |s| {
                                r.sendJson(s) catch return;
                            } else {
                                std.debug.print("Error\n", .{});
                                r.setStatus(.internal_server_error);
                                r.sendJson("{ \"status\": \"unable to render\"}") catch return;
                            }
                        } else |err| {
                            std.debug.print("Error: {}\n", .{err});
                            r.setStatus(.not_found);
                            r.sendJson("{ \"status\": \"not found\"}") catch return;
                        }
                    }
                }
            }
        }
    }
}

// shouldn't we just return which user is in which task?
fn listTasks(self: *Self, r: zap.SimpleRequest) void {
    var buf: [100 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var string = std.ArrayList(u8).init(fba.allocator());
    const t = self.tasks.json_template.root;
    if (t.jsonStringify(.{}, string.writer())) {
        r.sendJson(string.items) catch return;
    } else |err| {
        std.debug.print("/tasks LIST Error: {}\n", .{err});
        r.setStatus(.not_found);
        r.sendJson("{ \"status\": \"not found\"}") catch return;
    }
}
