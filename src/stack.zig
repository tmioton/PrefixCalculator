const std = @import("std");
const token_max = @import("constants.zig").token_max;

pub fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();

        data: [token_max]T = undefined,
        len: usize = 0,

        pub fn init() Self {
            return .{};
        }

        /// Empty the stack.
        pub fn reset(self: *Self) void {
            self.data = undefined;
            self.len = 0;
        }

        /// Add an item to the end of the stack.
        pub fn push(self: *Self, value: T) error{full}!void {
            if (self.len == token_max) return error.full;
            self.data[self.len] = value;
            self.len += 1;
        }

        /// Remove an item from the end of the stack.
        pub fn pop(self: *Self) ?T {
            if (self.len == 0) return null;
            self.len -= 1;
            return self.data[self.len];
        }
    };
}
