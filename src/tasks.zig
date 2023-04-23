const std = @import("std");
json_template: std.json.ValueTree = undefined,

const Self = @This();

const dummy_data_json = @embedFile("data/mustache_data_2.json");

pub fn init(a: std.mem.Allocator) !Self {
    var parser = std.json.Parser.init(a, false);
    return .{
        .json_template = try parser.parse(dummy_data_json),
    };
}
