const std = @import("std");

fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();

        const capacity = 256;

        data: [capacity]T = undefined,
        len: usize = 0,

        fn init() Self {
            return .{};
        }

        fn reset(self: *Self) void {
            self.data = undefined;
            self.len = 0;
        }

        fn push(self: *Self, value: T) error{full}!void {
            if (self.len == Self.capacity) return error.full;
            self.data[self.len] = value;
            self.len += 1;
        }

        fn pop(self: *Self) ?T {
            if (self.len == 0) return null;
            self.len -= 1;
            return self.data[self.len];
        }
    };
}

const TokenStack = Stack(Token);

const OperandStack = Stack(f64);

const TokenType = enum(u8) {
    operand,
    operator,
};

const Operator = enum { add, sub, mul, div };

const Token = union(TokenType) {
    operand: f64,
    operator: Operator,
};

fn sToF(string: []const u8) ?f64 {
    var total: f64 = 0;
    for (string) |char| {
        if (char < 48 or char > 57) {
            return null;
        }
        total = (total * 10) + (@as(f64, @floatFromInt(char - 48)));
    }
    return total;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const operators = [_]Operator{ .add, .sub, .mul, .div };

    var tokens = TokenStack.init();
    {
        var arg_buffer: [1024]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&arg_buffer);
        const allocator = fba.allocator();
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit(); // Technically we don't need to free, but it's a noop.

        _ = args.skip();
        while (args.next()) |arg| {
            if (arg.len == 0) continue;

            const operand = sToF(arg);
            const operator: ?Operator = for (operators) |op| {
                if (std.mem.eql(u8, @tagName(op), arg)) break op;
            } else null;

            if (operand == null and operator == null) {
                try stderr.print("Invalid operator or operand: {s}\n", .{arg});
                return;
            }

            tokens.push(if (operand != null) .{ .operand = operand.? } else .{ .operator = operator.? }) catch {
                try stderr.print("Exceeded maximum count of operands and operators.\n", .{});
                return;
            };
        }
    }

    // add 1 mul sub 3 2 4
    // Add 4 to stack.
    // Add 2 to stack.
    // Add 3 to stack.
    // sub pops last 2 numbers and adds result to stack.
    // mul pops last 2 numbers and adds result to stack.
    // Add 1 to stack.
    // add pops last 2 numbers and adds result to stack.
    // No more tokens, pop result from stack.

    var operands = OperandStack.init();
    while (tokens.pop()) |token| {
        switch (token) {
            .operand => |operand| {
                operands.push(operand) catch {
                    try stderr.print("Exceeded maximum operand count.\n", .{});
                    return;
                };
            },
            .operator => |operator| {
                // Check length here to avoid duplicated checking below.
                if (operands.len < 2) {
                    try stderr.print("Operator missing required operands.\n", .{});
                    return;
                }
                const a = operands.pop().?;
                const b = operands.pop().?;
                operands.push(switch (operator) {
                    .add => a + b,
                    .sub => a - b,
                    .mul => a * b,
                    .div => a / b,
                }) catch unreachable; // We just pulled two operands off, it's impossible to not have space.
            },
        }
    }

    if (operands.len < 1) {
        try stderr.print("No result!\n", .{});
        return;
    }
    try stdout.print("{d}\n", .{operands.pop().?});
}
