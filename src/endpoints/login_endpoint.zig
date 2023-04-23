const std = @import("std");
const zap = @import("zap");
const Users = @import("../users.zig");
const userIdFromQuery = @import("../common.zig").userIdFromQuery;

alloc: std.mem.Allocator = undefined,
endpoint: zap.SimpleEndpoint = undefined,

pub const Self = @This();


pub fn getLoginEndpoint(self: *Self) *zap.SimpleEndpoint {
    return &self.endpoint;
}

/// We return these errors when validating the login URI
const LoginError = error{
    /// No experimentid was provided in the login request
    MissingExperimentId,
    /// No panel (prolific) id was provided in the login request
    MissingPanelId,
};

fn validateLoginRequest(r: zap.SimpleRequest) !void {
    const uri = std.Uri.parse(r.
}
