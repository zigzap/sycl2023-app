const std = @import("std");
json_template: std.json.ValueTree = undefined,

const Self = @This();


pub fn init(a: std.mem.Allocator) !Self {
    var parser = std.json.Parser.init(a, false);
    return .{
        .json_template = try parser.parse(dummy_data_json),
    };
}
