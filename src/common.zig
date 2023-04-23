const std = @import("std");

pub fn userIdFromQuery(query: []const u8) ?[]const u8 {
    var startpos: usize = 0;
    var endpos: usize = query.len;
    if (std.mem.indexOfScalar(u8, query, '&')) |amp| {
        endpos = amp;
    }
    // search for =
    if (std.mem.indexOfScalar(u8, query[startpos..endpos], '=')) |eql| {
        startpos = eql;
    }
    const idstr = query[startpos + 1 .. endpos];
    return idstr;
}
