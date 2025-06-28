const std = @import("std");
const assert = std.debug.assert;

const string_max = @import("constants.zig").string_max;
const token_max = @import("constants.zig").token_max;

const Stack = @import("stack.zig").Stack;

const TokenStack = @import("TokenStack.zig");
const Operator = TokenStack.Operator;

const InputStore = @import("InputStore.zig");

const Range = struct { start: usize, end: usize };

const ErrorString = struct {
    data: [string_max]u8 = undefined,
    len: usize = 0,

    fn fromInput(store: *const InputStore, index: usize) ErrorString {
        var self: ErrorString = .{};
        const item = store.slices[index];
        @memset(self.data[0..item.head], ' ');
        @memset(self.data[item.head .. item.head + item.len], '^');
        self.len = item.head + item.len;
        return self;
    }

    fn fromInputRange(store: *const InputStore, range: Range) ErrorString {
        var self: ErrorString = .{};
        const start = store.slices[range.start];
        @memset(self.data[0..start.head], ' ');
        var len: usize = 0;
        for (range.start..range.end) |i| {
            len += store.slices[i].len;
        }

        // Account for spaces in input store.
        len += (range.end - 1) - range.start;
        @memset(self.data[start.head .. start.head + len], '^');
        self.len = start.head + len;
        return self;
    }

    fn get(self: *const ErrorString) []const u8 {
        return self.data[0..self.len];
    }
};

fn parseOperator(in: []const u8) ?Operator {
    // Iterate over the names of the Operator enum and see if the input matches any.
    for (std.meta.tags(Operator)) |op| {
        if (std.mem.eql(u8, @tagName(op), in)) return op;
    }
    return null;
}

pub fn main() !u8 {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    //const type_in_question = Token;
    //try stdout.print("Size of {s}: {}\n", .{ @typeName(type_in_question), @sizeOf(type_in_question) });

    var input = InputStore.init();
    var tokens = TokenStack.init();
    {
        var arg_buffer: [string_max]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&arg_buffer);
        const allocator = fba.allocator();
        var args = std.process.argsWithAllocator(allocator) catch {
            try stderr.print("Excessive input.", .{});
            return 1;
        };
        defer args.deinit(); // Technically we don't need to free, but it's a noop.

        const command = std.fs.path.basename(args.next().?); // The program has to have a first arg.
        if (command.len > InputStore.limit_string) {
            try stderr.print("Executable name is excessive.\n", .{});
            return 1;
        }
        input.push(command) catch unreachable;

        while (args.next()) |arg| {
            if (arg.len == 0) continue;
            if (arg.len > InputStore.limit_string) {
                try stderr.print("Excessive argument length.\n", .{});
                return 1;
            }

            // Handle flags here.

            input.push(arg) catch |err| switch (err) {
                error.full => {
                    try stderr.print("Exceeded maximum count of operands and operators.\n", .{});
                    return 1;
                },
                error.out_of_range => unreachable,
            };
        }
    }

    if (input.len == 1) {
        const binary = input.get(0);
        // Print the help text.
        try stderr.print(
            \\Command-line prefix calculator.
            \\Example input:
            \\{s} add 1 1
            \\{s} add add 1 1 1
            \\{s} 1
            \\
        , .{ binary, binary, binary });
        return 1;
    }

    // TODO: Rewrite this:
    //
    // add add 1 1 1
    // push add. Add requires 2 operands and returns 1 - -1 remaining operands.
    // push add. Add requires 2 operands and returns 1 - -2 remaining operands.
    // push 1. -1 remaining operands.
    // push 1. 0 remaining operands - program has to end with 1 operand remaining for output.
    // push 1. 1 remaining operands - valid calculation.
    // add add 1 add 1 1 1

    // A tree will allow us to work backwards on tokenization.
    // We would have to store invalid input if we want "unused input" to be higher priority than "invalid operand".
    var remaining_operands: isize = 0;
    for (1..input.len) |i| {
        const arg = input.get(i);
        (push: {
            // parseFloat will exit immediately if the input doesn't match a number, so we try that first.
            if (std.fmt.parseFloat(f64, arg) catch null) |operand| {
                remaining_operands += 1;
                if (i == 1) {
                    @branchHint(.unlikely); // Just a good place to use this, even if it can get optimized away.
                    if (input.len == 2) {
                        tokens.pushOperand(operand) catch unreachable;
                        break; // Support single operand return.
                    }
                    break :push; // Handled by the needed_operands == 0 check below.
                }
                break :push tokens.pushOperand(operand);
            } else if (parseOperator(arg)) |operator| {
                remaining_operands -= 1; // Takes 2 and returns 1.
                break :push tokens.pushOperator(operator);
            } else {
                const error_string = ErrorString.fromInput(&input, i);
                try stderr.print("Invalid operator or operand.\n{s}\n{s}\n", .{ input.all(), error_string.get() });
                return 1;
            }
        }) catch {
            const error_string = ErrorString.fromInput(&input, i);
            try stderr.print("Exceeded maximum count of operands and operators.\n{s}\n{s}\n", .{ input.all(), error_string.get() });
            return 1;
        };

        // If we reach 0 and there's still input we error the rest of the input as excessive.
        if (remaining_operands == 1 and i < input.len - 1) {
            const error_string = ErrorString.fromInputRange(&input, Range{ .start = i + 1, .end = input.len });
            try stderr.print("Unused input.\n{s}\n{s}\n", .{ input.all(), error_string.get() });
            return 1;
        }
    }

    // If there are more operators than operands we work backwards to figure out which operand is missing input.
    // Is a tree more efficient than backtracking?
    if (remaining_operands < 1) {
        var token_input: usize = tokens.len;
        var operands: usize = 0;
        while (tokens.pop()) |token| {
            switch (token) {
                .operand => {
                    operands += 1;
                },
                .operator => {
                    if (operands < 2) {
                        const error_string = ErrorString.fromInput(&input, token_input);
                        try stderr.print("Operator missing required operands.\n{s}\n{s}\n", .{ input.all(), error_string.get() });
                        return 1;
                    }
                    operands -= 1;
                },
            }
            token_input -= 1;
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
    //
    // Actually, we might want to just store the tokens and waste the space instead of spending time constructing the token on request.

    var token_input: usize = tokens.len;
    var operands = Stack(f64).init();
    var operand_ranges = Stack(Range).init();
    while (tokens.pop()) |token| {
        switch (token) {
            .operand => |operand| {
                operands.push(operand) catch @panic("invalid state: stack overflow");

                // This and the operand stack have the same size. If that one didn't error, this one can't.
                operand_ranges.push(.{ .start = token_input, .end = token_input + 1 }) catch unreachable;
            },
            .operator => |operator| {
                // Can assert length here because we check for missing operands above.
                if (operands.len < 2) @panic("invalid state: missing operands");

                const a = operands.pop().?;
                const b = operands.pop().?;
                operands.push(switch (operator) {
                    .add => a + b,
                    .sub => a - b,
                    .mul => a * b,
                    .div => a / b,
                    .pow => std.math.pow(f64, a, b),
                }) catch unreachable; // We just pulled two operands off, it's impossible to not have space.

                _ = operand_ranges.pop().?;
                const b_range = operand_ranges.pop().?;
                operand_ranges.push(.{ .start = token_input, .end = b_range.end }) catch unreachable;
            },
        }
        token_input -= 1;
    }

    // In addition to converting this to detect unused values before processing,
    // I would also like to detect unused values before checking for missing operands.
    if (operands.len < 1) {
        try stdout.print("nil", .{});
        return 1;
    } else if (operands.len > 1) {
        @panic("invalid state: unused input");
    }
    try stdout.print("{d}", .{operands.pop().?});
    return 0;
}
