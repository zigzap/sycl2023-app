//! The experiments collection
//!
//! A string hashmap: experiment id -> experiment instance

const std = @import("std");
const Users = @import("users.zig");
const jutils = @import("jsonutils.zig");

allocator: std.mem.Allocator = undefined,
experiments: ExperimentMap = undefined,
lock: std.Thread.Mutex = .{},

const ExperimentMap = std.StringHashMap(Experiment);
pub const Self = @This();

pub const ExperimentError = error{
    InvalidValue,
    InvalidType_StringExpected,
    InvalidType_IntExpected,
    MissingField,
    NotImplemented,
};

/// Experiment conditions, specific for this kind of online experiment.
///
/// Note: if we want to make it all more generic, we'll just abandon this enum
///       and just work with conditions as strings as they are received from JSON.
///       The reason this enum exists, is so that we can quickly compare.
///       So branching in some API code, depending on experiment condition does
///       not involve a string comparison every time.
pub const ExperimentCondition = enum {
    HumanInfluencer,
    VirtualInfluencer,

    const Fields = @typeInfo(ExperimentCondition).Enum.fields;

    // see https://zig.news/david_vanderson/howto-pair-strings-with-enums-9ce
    pub const StrTable = [Fields.len][:0]const u8{
        "HumanInfluencer",
        "VirtualInfluencer",
    };

    pub fn str(self: ExperimentCondition) [:0]const u8 {
        return StrTable[@enumToInt(self)];
    }

    pub fn jsonStringify(
        self: *const ExperimentCondition,
        options: std.json.StringifyOptions,
        out_stream: anytype,
    ) @TypeOf(out_stream).Error!void {
        _ = options;
        try out_stream.writeByte('"');
        try out_stream.writeAll(self.str());
        return out_stream.writeByte('"');
    }

    pub fn fromString(s: []const u8) !ExperimentCondition {
        inline for (Fields) |f| {
            if (std.mem.eql(u8, s, StrTable[f.value])) return @intToEnum(ExperimentCondition, f.value);
        }
        return ExperimentError.InvalidValue;
    }
};

/// Experiment Status
pub const Status = enum {
    Created,
    Running,
    Finished,
    Terminated,

    const Fields = @typeInfo(Status).Enum.fields;

    pub const StrTable = [Fields.len][:0]const u8{
        "CREATED",
        "RUNNING",
        "FINISHED",
        "TERMINATED",
    };

    pub fn str(self: Status) [:0]const u8 {
        return StrTable[@enumToInt(self)];
    }

    pub fn jsonStringify(
        self: *const Status,
        options: std.json.StringifyOptions,
        out_stream: anytype,
    ) @TypeOf(out_stream).Error!void {
        _ = options;
        try out_stream.writeByte('"');
        try out_stream.writeAll(self.str());
        return out_stream.writeByte('"');
    }

    pub fn fromString(s: []const u8) !Status {
        inline for (Fields) |f| {
            if (std.mem.eql(u8, s, StrTable[f.value])) return @intToEnum(Status, f.value);
        }
        return ExperimentError.InvalidValue;
    }
};

/// The experiment "description". Usually sourced from a JSON file.
/// In addition, the participants (users) are also part of the struct.
pub const Experiment = struct {
    /// the unique id of this run
    run_id: []const u8,
    prolific_id: []const u8,
    title: []const u8,
    short_desc: []const u8,
    status: Status,

    /// Visiting but not starting -> expires in 15min
    /// TODO: not sure if we need that with prolific
    visit_expires_s: usize = 900,

    /// The conditions are vital to the kind of experiment. Hence, they are not
    /// generic JSON objects but specified in zig.
    condition: ExperimentCondition,

    /// Number of probands required until the experiment is considered finished.
    /// Prolific should take care we won't exceed this number.
    num_required_probands: usize,

    /// Number of probands to prepare in memory. Prepare at least twice as many
    /// as `num_required_probands` to account for timeouts and non-completes.
    num_prepared_probands: usize,

    msg_study_closed: []const u8,
    msg_already_participated: []const u8,
    msg_login_only_once: []const u8,
    msg_login_time_window_expired: []const u8,

    timeout_seconds: usize,
    creation_timestamp: []const u8,
    activation_timestamp: ?[]const u8,
    termination_timestamp: ?[]const u8,

    initial_task: []const u8 = "0",

    /// Tasks: we want to be flexible while implementing the frontend, hence we
    /// leave stuff here as JSON object map.
    tasks: ?std.json.Value,

    /// Products for the posts and shop. We want to be flexible, so we leave
    /// them as JSON object map.
    products: ?std.json.Value,

    /// Defined insta posts for all conditions
    posts: ?std.json.Value,

    /// All the prepared users, created upon instantiation
    users: Users,

    /// JSON parser for the experiment (when creating from disk)
    /// We need to hold on to it after parsing, as it contains the JSON values
    /// we keep using. (E.g.: products, tasks, etc.).
    json_parser: ?std.json.Parser = null,
    /// Parsed JSON when creating from disk. See above (parser) why we need to
    /// hold on to this and not discard after parsing.
    json_parsed: ?std.json.ValueTree = null,

    /// export Experiment to JSON and save it to disk.
    pub fn persist(e: *Experiment, a: std.mem.Allocator) !void {
        const json_buf = try std.json.stringifyAlloc(
            a,
            .{
                .run_id = e.run_id,
                .prolific_id = e.prolific_id,
                .title = e.title,
                .short_desc = e.short_desc,
                .status = e.status,
                .visit_expires_s = e.visit_expires_s,
                .condition = e.condition,
                .num_required_probands = e.num_required_probands,
                .num_prepared_probands = e.num_prepared_probands,
                .msg_study_closed = e.msg_study_closed,
                .msg_already_participated = e.msg_already_participated,
                .msg_login_only_once = e.msg_login_only_once,
                .msg_login_time_window_expired = e.msg_login_time_window_expired,
                .activation_timestamp = e.activation_timestamp,
                .termination_timestamp = e.termination_timestamp,
                .initial_task = e.initial_task,
                .tasks = e.tasks,
                .products = e.products,
                .posts = e.posts,
            },
            .{},
        );
        _ = json_buf;
    }

    pub fn deinit(self: *Experiment) void {
        if (self.json_parsed) |*p| {
            p.deinit();
        }
        if (self.json_parser) |*p| {
            p.deinit();
        }
    }
};

pub const data_path = "data";
pub const runtime_path = "runtime";

/// the path where experiment runs are persisted to so they can be re-loaded via
/// createExperimentFromJson(). Usually: `./runtime/state/experiments`.
pub const state_path = runtime_path ++ "/state/experiments";

pub const template_path = data_path ++ "/templates";

pub const template_max_filesize = 1024 * 1024;

/// Create Experiment from Template - used from the REST API
/// Also, gets persisted in `state_path` (runtime/state/experiments)
/// The experiment is automatically added to the experiments map
/// Templates must reside in the pre-defined templates directory.
pub fn createExperimentFromTemplate(
    self: *Self,
    template_name: []const u8,
    json_params: std.json.ObjectMap,
) !*Experiment {
    // 1. Load the file -> string
    var fname_buf: [1024]u8 = undefined;
    const fname = try std.fmt.bufPrint(fname_buf, "{s}/{s}", .{ template_path, template_name });

    const template_buf = try std.fs.cwd().readFileAlloc(self.allocator, fname, template_max_filesize);
    defer self.allocator.free(template_buf);

    // 2. replace $-strings with json_params
    var it = json_params.iterator();
    var replaced: []const u8 = template_buf;

    for (it.next()) |entry| {
        // we expect a string key and a string value
        const needle = entry.key_ptr;

        // JSON object value is a tagged union
        switch (entry.value_ptr.*) {
            .String => |s| {
                if (replaced != template_buf) {
                    // free temporaries
                    self.allocator.free(replaced);
                }
                replaced = try std.mem.replaceOwned(u8, self.allocator, replaced, needle, s);
            },
            else => return ExperimentError.InvalidType_StringExpected,
        }
    }
    defer self.allocator.free(replaced);

    // now the JSON is in `repaced`
    if (try self.createExperimentFromJson(replaced, false)) |experiment| {
        // 3. Persist the experiment to disk
        try experiment.persist();
        return experiment;
    } else unreachable; // cannot be null
}

/// Create Experiment by loading its JSON from disk.
/// Useful for after a crash / shutdown of the server.
pub fn createExperimentFromFile(self: *Self, json_path: []const u8, only_running: bool) !?*Experiment {
    const json = try std.fs.cwd().readFileAlloc(self.allocator, json_path, template_max_filesize);
    defer self.allocator.free(json);
    var experiment: ?*Experiment = try self.createExperimentFromJson(json, only_running);
    return experiment;
}

/// Create Experiment from JSON. Used by the other create functions.
pub fn createExperimentFromJson(self: *Self, json: []const u8, only_running: bool) !?*Experiment {
    var parser = std.json.Parser.init(self.allocator, true); // strings need to be copied
    errdefer parser.deinit();
    var parsed = try parser.parse(json);
    errdefer parsed.deinit();
    var r = parsed.root;

    // "parse" object map into experiment
    // start with json.root : std.json.Value
    const num_required_probands = try jutils.getJsonUsizeValue(r, "num_required_probands");
    var tasks: ?std.json.Value = null;
    var products: ?std.json.Value = null;
    var posts: ?std.json.Value = null;

    if (r.Object.get("tasks")) |the_tasks| { // FIXME: another temporary, tasks can be huge
        tasks = the_tasks;
    }
    if (r.Object.get("products")) |the_products| { // FIXME: another temporary, products can be huge
        products = the_products;
    }
    if (r.Object.get("posts")) |the_posts| { // FIXME: another temporary, posts can be huge
        posts = the_posts;
    }
    var experiment = Experiment{ // FIXME: is this a temporary?
        .run_id = try jutils.getJsonStringValue(r, "run_id"),
        .prolific_id = try jutils.getJsonStringValue(r, "prolific_id"),
        .title = try jutils.getJsonStringValue(r, "title"),
        .short_desc = try jutils.getJsonStringValue(r, "short_desc"),
        .status = try Status.fromString(try jutils.getJsonStringValue(r, "status")),
        .visit_expires_s = try jutils.getJsonUsizeValue(r, "visit_expires_s"),
        .condition = try ExperimentCondition.fromString(try jutils.getJsonStringValue(r, "condition")),
        .num_required_probands = num_required_probands,
        .num_prepared_probands = try jutils.getJsonUsizeValue(r, "num_prepared_probands"),
        .msg_study_closed = try jutils.getJsonStringValue(r, "msg_study_closed"),
        .msg_already_participated = try jutils.getJsonStringValue(r, "msg_already_participated"),
        .msg_login_only_once = try jutils.getJsonStringValue(r, "msg_login_only_once"),
        .msg_login_time_window_expired = try jutils.getJsonStringValue(r, "msg_login_time_window_expired"),
        .timeout_seconds = try jutils.getJsonUsizeValue(r, "timeout_seconds"),
        .creation_timestamp = try jutils.getJsonStringValue(r, "creation_timestamp"),

        // the following two might be present in the JSON from a persisted
        // experiment that we want to reload from disk.
        .activation_timestamp = jutils.getJsonStringValue(r, "activation_timestamp") catch null,
        .termination_timestamp = jutils.getJsonStringValue(r, "termination_timestamp") catch null,

        .initial_task = try jutils.getJsonStringValue(r, "initial_task"),

        // optional
        .tasks = tasks, // FIXME: do we need to check for type?
        .products = products,
        .posts = posts, // FIXME: do we need to check for type?
        .users = try Users.init(self.allocator, num_required_probands),

        .json_parser = parser,
        .json_parsed = parsed,
    };

    // (insert experiment into hashmap)
    if (experiment.status == .Finished or experiment.status == .Terminated) {
        if (only_running) {
            experiment.deinit();
            return null;
        }
    }

    // TODO: load users from disk if present
    if (true) return ExperimentError.NotImplemented;

    try self.experiments.put(experiment.run_id, experiment);
    return self.experiments.getPtr(experiment.run_id);
}

/// Attempt to restore all (optional: running) experiments from persisted state
pub fn restoreState(self: *Self, only_running: bool) ![]Experiment {
    _ = self;
    _ = only_running;
    return ExperimentError.NotImplemented;
}

/// Save all experiments to disk
pub fn saveState(self: *Self) !void {
    _ = self;
    return ExperimentError.NotImplemented;
}

/// Return an empty Experiments collection. Initializes the hashmap.
pub fn init(a: std.mem.Allocator) Self {
    return .{
        .allocator = a,
        .experiments = ExperimentMap.init(a),
    };
}

pub fn deinit(self: *Self) void {
    var it = self.experiments.valueIterator();
    while (it.next()) |e| {
        e.deinit();
        e.users.deinit();
    }
    self.experiments.deinit();
}
