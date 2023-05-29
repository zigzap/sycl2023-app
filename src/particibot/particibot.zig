const std = @import("std");
const Bot = @import("bot.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var bot = Bot.init(allocator, 1, "http://127.0.0.1:5000/sycl-api");
    defer bot.deinit();

    while (bot.state != .done) {
        try bot.step();
    }
}
