//! Structure for storing command-line inputs for good error output.
//!  Automatically adds spaces between arguments.

const std = @import("std");
const string_max = @import("constants.zig").string_max;
const token_max = @import("constants.zig").token_max;

pub const InputStore = @This();

pub const StoreSlice = struct {
    head: u24, // u16, but we'll just use the extra space. Only 1 byte wasted as opposed to 7 with Stack(Token).
    len: u8,
};

pub const limit_head = std.math.maxInt(@FieldType(StoreSlice, "head"));
pub const limit_string = std.math.maxInt(@FieldType(StoreSlice, "len"));

pub const capacity = token_max + 1;

strings: [string_max]u8 = undefined,
slices: [capacity]StoreSlice = undefined,
head: usize = 0,
len: usize = 0,

pub fn init() InputStore {
    return .{};
}

/// Store a string.
pub fn push(self: *InputStore, value: []const u8) error{ full, out_of_range }!void {
    if (self.head + value.len > limit_head or value.len > limit_string) return error.out_of_range;
    if (self.len == capacity or self.head + value.len > string_max) return error.full;
    if (self.len != 0) {
        self.strings[self.head] = ' ';
        self.head += 1;
    }
    std.mem.copyForwards(u8, self.strings[self.head..string_max], value);
    self.slices[self.len] = .{ .head = @truncate(self.head), .len = @truncate(value.len) };
    self.head += value.len;
    self.len += 1;
}

/// Return the nth string pushed into the store.
pub fn get(self: *const InputStore, n: usize) []const u8 {
    const slice = self.slices[n];
    return self.strings[slice.head .. slice.head + slice.len];
}

/// Join all strings together into a command-line representation.
pub fn all(self: *const InputStore) []const u8 {
    return self.strings[0..self.head];
}
