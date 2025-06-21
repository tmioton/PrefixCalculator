const std = @import("std");
const token_max = @import("constants.zig").token_max;

pub const TokenStack = @This();

pub const Operator = enum { add, sub, mul, div, pow };

// This can probably be made into a generic, but it's fine to stay like this.
pub const Type = enum(u8) { operand, operator };
pub const Data = union { operand: f64, operator: Operator };
pub const Token = union(Type) { operand: f64, operator: Operator };
pub const PushError = error{full};

tokens: [token_max]Data = undefined,
types: [token_max]Type = undefined,
len: usize = 0,

pub fn init() TokenStack {
    return .{};
}

inline fn push_operand_noerror(self: *TokenStack, operand: f64) void {
    self.tokens[self.len] = .{ .operand = operand };
    self.types[self.len] = .operand;
    self.len += 1;
}

pub fn push_operand(self: *TokenStack, operand: f64) PushError!void {
    if (self.len == token_max) return PushError.full;
    return self.push_operand_noerror(operand);
}

inline fn push_operator_noerror(self: *TokenStack, operator: Operator) void {
    self.tokens[self.len] = .{ .operator = operator };
    self.types[self.len] = .operator;
    self.len += 1;
}

pub fn push_operator(self: *TokenStack, operator: Operator) PushError!void {
    if (self.len == token_max) return PushError.full;
    return self.push_operator_noerror(operator);
}

/// Add a token to the end of the stack.
pub fn push(self: *TokenStack, value: Token) PushError!void {
    if (self.len == token_max) return error.full;
    return switch (value) {
        .operand => |operand| self.push_operand_noerror(operand),
        .operator => |operator| self.push_operator_noerror(operator),
    };
}

/// Remove a token from the end of the stack.
pub fn pop(self: *TokenStack) ?Token {
    if (self.len == 0) return null;
    self.len -= 1;
    return switch (self.types[self.len]) {
        .operand => .{ .operand = self.tokens[self.len].operand },
        .operator => .{ .operator = self.tokens[self.len].operator },
    };
}
