const std = @import("std");

const Response = struct {
    length: usize,
    micoSeconds: i64,
};

pub fn post(allocator: std.mem.Allocator, url: []const u8, message_json: []const u8, output_buffer: []u8) !Response {
    // url
    const uri = try std.Uri.parse(url);

    // http headers
    var h = std.http.Headers{ .allocator = allocator };
    defer h.deinit();
    try h.append("accept", "*/*");
    try h.append("Content-Type", "application/json");

    // client
    var http_client: std.http.Client = .{ .allocator = allocator };
    defer http_client.deinit();

    // request
    var req = try http_client.request(.POST, uri, h, .{});
    defer req.deinit();

    req.transfer_encoding = .chunked;

    // connect, send request
    try req.start();

    // send POST payload
    try req.writer().writeAll(message_json);
    try req.finish();

    // wait for response
    const time_start = std.time.microTimestamp();
    try req.wait();
    const response_len = try req.readAll(output_buffer);
    const time_end = std.time.microTimestamp();
    return .{
        .length = response_len,
        .micoSeconds = time_end - time_start,
    };
}

pub fn get(allocator: std.mem.Allocator, url: []const u8, output_buffer: []u8) !Response {
    // url
    const uri = try std.Uri.parse(url);

    // http headers
    var h = std.http.Headers{ .allocator = allocator };
    defer h.deinit();
    try h.append("accept", "*/*");

    // client
    var http_client: std.http.Client = .{ .allocator = allocator };
    defer http_client.deinit();

    // request
    var req = try http_client.request(.GET, uri, h, .{});
    defer req.deinit();

    // connect, send request
    try req.start();

    // wait for response
    const time_start = std.time.microTimestamp();
    try req.wait();
    const response_len = try req.readAll(output_buffer);
    const time_end = std.time.microTimestamp();
    return .{
        .length = response_len,
        .micoSeconds = time_end - time_start,
    };
}
