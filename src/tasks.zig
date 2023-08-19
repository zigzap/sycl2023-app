const std = @import("std");

allocator: std.mem.Allocator,
json_template: ?std.json.Parsed(std.json.Value) = null,
json_template_buf: []const u8 = undefined,
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
    self.json_template_buf = try std.fs.cwd().readFileAlloc(self.allocator, self.json_template_filn, self.json_template_max_filesize);
    // TODO: free potential prev buf: defer self.allocator.free(template_buf);
    self.json_template = try std.json.parseFromSlice(std.json.Value, self.allocator, self.json_template_buf, .{});
}
