const std = @import("std");

pub const JsonError = error{
    InvalidType_StringExpected,
    InvalidType_IntExpected,
    InvalidType_ObjectExpected,
    InvalidType_ArrayExpected,
    MissingField,
};

pub fn getJsonStringValue(json: std.json.Value, key: []const u8) ![]const u8 {
    if (json.object.get(key)) |value| {
        switch (value) {
            .string => |s| return s,
            else => return JsonError.InvalidType_StringExpected,
        }
    } else {
        return JsonError.MissingField;
    }
}

pub fn getJsonUsizeValue(json: std.json.Value, key: []const u8) !usize {
    if (json.object.get(key)) |value| {
        switch (value) {
            .integer => |i| return @intCast(usize, i),
            else => return JsonError.InvalidType_IntExpected,
        }
    } else {
        return JsonError.MissingField;
    }
}

pub fn getJsonObjectValue(json: std.json.Value, key: []const u8) !std.json.Value {
    if (json.object.get(key)) |value| {
        switch (value) {
            .object => |_| return value,
            else => return JsonError.InvalidType_ObjectExpected,
        }
    } else {
        return JsonError.MissingField;
    }
}

pub fn getJsonObject(json: std.json.Value, key: []const u8) !std.json.Value {
    if (json.object.get(key)) |value| {
        switch (value) {
            .object => |s| return s,
            else => return JsonError.InvalidType_ObjectExpected,
        }
    } else {
        return JsonError.MissingField;
    }
}
