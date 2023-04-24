const std = @import("std");
json_template: std.json.ValueTree = undefined,

const Self = @This();

const dummy_data_json = @embedFile("data/sycl2023-survey.json");

pub fn init(a: std.mem.Allocator) !Self {
    var parser = std.json.Parser.init(a, false);
    return .{
        .json_template = try parser.parse(dummy_data_json),
    };
}
