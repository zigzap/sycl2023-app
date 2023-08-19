const std = @import("std");
const Bot = @import("bot.zig");

fn run_bot(alloc: std.mem.Allocator, number: usize) !void {
    var bot = Bot.init(alloc, number, "http://127.0.0.1:5000/sycl-api");
    defer bot.deinit();
    while (bot.state != .done) {
        bot.step() catch return;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    var allocator = gpa.allocator();

    var args = std.process.args();
    var num_threads: usize = 1;
    _ = args.skip();

    if (args.next()) |threadcount| {
        std.debug.print("{s} THREADS\n", .{threadcount});
        num_threads = try std.fmt.parseInt(usize, threadcount, 10);
    }

    var repetitions: usize = 1;
    if (args.next()) |reps| {
        std.debug.print("{s} REPETITIONS\n", .{reps});
        repetitions = try std.fmt.parseInt(usize, reps, 10);
    }

    for (0..repetitions) |_| {
        var threads = std.ArrayList(std.Thread).init(allocator);
        for (0..num_threads) |i| {
            const t = try std.Thread.spawn(.{}, run_bot, .{ allocator, i });
            threads.append(t) catch break;
        }
        for (threads.items) |t| {
            t.join();
        }
    }

    // OMG, never show this to anyone until fixed 😊
    // TODO: fix mem leak
    // if (gpa.detectLeaks() == true) {
    //     std.log.err("FCK!\n", .{});
    // }
}
