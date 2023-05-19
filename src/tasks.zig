const std = @import("std");

allocator: std.mem.Allocator,
json_template: ?std.json.ValueTree = null,
json_template_filn: []const u8 = undefined,
json_template_max_filesize: usize = 1024 * 1024,

const Self = @This();

const dummy_data_json = @embedFile("data/sycl2023-survey.json");

pub fn init(a: std.mem.Allocator, template_filn: []const u8) !Self {
    const filn_copy = try a.dupe(u8, template_filn);
    var ret: Self = .{
        .allocator = a,
        .json_template_filn = filn_copy,
    };
    try ret.update();
    return ret;
}

/// Update the template from disk
pub fn update(self: *Self) !void {
    const template_buf = try std.fs.cwd().readFileAlloc(self.allocator, self.json_template_filn, self.json_template_max_filesize);
    defer self.allocator.free(template_buf);

    var parser = std.json.Parser.init(self.allocator, .alloc_always); // copy_strings!
    if (self.json_template) |*t| {
        t.deinit();
    }
    self.json_template = try parser.parse(template_buf);
}
