const std = @import("std");
const Bot = @import("bot.zig");

fn run_bot(alloc: std.mem.Allocator, number: usize) !void {
    var bot = Bot.init(alloc, number, "http://127.0.0.1:5000/sycl-api");
    defer bot.deinit();
    while (bot.state != .done) {
        try bot.step();
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    var allocator = gpa.allocator();

    var args = std.process.args();
    var num_bots: usize = 1;
    _ = args.skip();

    if (args.next()) |howmany| {
        std.debug.print("{s} BOTS\n", .{howmany});
        num_bots = try std.fmt.parseInt(usize, howmany, 10);
    }

    var threads = std.ArrayList(std.Thread).init(allocator);
    for (0..num_bots) |i| {
        const t = try std.Thread.spawn(.{}, run_bot, .{ allocator, i });
        try threads.append(t);
    }
    for (threads.items) |t| {
        t.join();
    }
}
