const std = @import("std");

pub fn bundledOrLocalFilePathOwned(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const exe_path = std.fs.selfExeDirPathAlloc(allocator) catch ".";
    defer allocator.free(exe_path);
    const bundled_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ exe_path, path });
    if (std.fs.openFileAbsolute(bundled_path, .{})) |file| {
        file.close();
        return bundled_path;
    } else |_| {
        return try allocator.dupe(u8, path);
    }
}

pub fn bundledOrLocalDirPathOwned(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const exe_path = std.fs.selfExeDirPathAlloc(allocator) catch ".";
    defer allocator.free(exe_path);
    const bundled_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ exe_path, path });
    var dir = std.fs.openDirAbsolute(bundled_path, .{}) catch {
        return try std.fs.cwd().realpathAlloc(allocator, path);
    };
    dir.close();
    return bundled_path;
}
