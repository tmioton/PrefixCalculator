const std = @import("std");

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

    fn from_input(store: *const InputStore, index: usize) ErrorString {
        var self: ErrorString = .{};
        const item = store.slices[index];
        @memset(self.data[0..item.head], ' ');
        @memset(self.data[item.head .. item.head + item.len], '^');
        self.len = item.head + item.len;
        return self;
    }

    fn from_input_range(store: *const InputStore, range: Range) ErrorString {
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

pub fn main() !u8 {
    // How do we add good error output?
    //  Try to determine if the input was meant to be an operand or operator. <- this probably requires an AST.
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
        // Print the help text.
        try stderr.print("", .{});
        return 1;
    }

    // add add 1 1 1 - Operand count since last operator wouldn't be even here.
    // push add. add needs two operands.
    // push add. add needs two operands and consumes one of the above.
    // push one. consume one of the above operands.
    // push one. consume one of the above operands.
    // push one. consume one of the above operands.
    // add add 1 add 1 1 1
    // If we reach 0 and there's still input we error the rest of the input as excessive.
    // If we reach the end of the input and still need operands we know there's an error so we work backwards.
    // Is a tree more efficient than that backwards lookup?
    // 1 1 add 1 1 - first two will drop needed_operands down to -2.
    // We want to support 1 number being the result.

    var needed_operands: usize = 0;
    for (1..input.len) |i| {
        const arg = input.get(i);
        const operand: ?f64 = std.fmt.parseFloat(f64, arg) catch null;
        // Iterate over the names of the Operator enum and see if the input matches any.
        const operator: ?Operator = for (std.meta.tags(Operator)) |op| {
            if (std.mem.eql(u8, @tagName(op), arg)) break op;
        } else null;

        if (operand == null and operator == null) {
            const error_string = ErrorString.from_input(&input, i);
            try stderr.print("Invalid operator or operand.\n{s}\n{s}\n", .{ input.all(), error_string.get() });
            return 1;
        }

        (push: {
            if (operand != null) {
                if (i == 1) {
                    @branchHint(.unlikely); // Just a good place to use this, even if it can get optimized away.
                    if (input.len == 2) {
                        tokens.push_operand(operand.?) catch unreachable;
                        break; // Support single operand return.
                    }
                    break :push; // Handled by the needed_operands == 0 check below.
                }
                needed_operands -= 1;
                break :push tokens.push_operand(operand.?);
            } else {
                needed_operands += 2;
                break :push tokens.push_operator(operator.?);
            }
        }) catch {
            const error_string = ErrorString.from_input(&input, i);
            try stderr.print("Exceeded maximum count of operands and operators.\n{s}\n{s}\n", .{ input.all(), error_string.get() });
            return 1;
        };

        if (needed_operands == 0 and i < input.len - 1) {
            const error_string = ErrorString.from_input_range(&input, Range{ .start = i + 1, .end = input.len });
            try stderr.print("Unused input.\n{s}\n{s}\n", .{ input.all(), error_string.get() });
            return 1;
        }
    }

    // TODO: Implement backtracking.

    // if (needed_operands > 0) {
    //     try stderr.print("Operator missing required operands.\n", .{});
    //     return 1;
    // }

    // add 1 mul sub 3 2 4
    // Add 4 to stack.
    // Add 2 to stack.
    // Add 3 to stack.
    // sub pops last 2 numbers and adds result to stack.
    // mul pops last 2 numbers and adds result to stack.
    // Add 1 to stack.
    // add pops last 2 numbers and adds result to stack.
    // No more tokens, pop result from stack.

    var token_input: usize = tokens.len;
    var operands = Stack(f64).init();
    var operand_ranges = Stack(Range).init();
    while (tokens.pop()) |token| {
        switch (token) {
            .operand => |operand| {
                operands.push(operand) catch {
                    try stderr.print("Exceeded maximum operand count.\n", .{});
                    return 1;
                };

                // This and the operand stack have the same size. If that one didn't error, this one can't.
                operand_ranges.push(.{ .start = token_input, .end = token_input + 1 }) catch unreachable;
            },
            .operator => |operator| {
                // Check length here to avoid duplicated checking below.
                if (operands.len < 2) {
                    const error_string = ErrorString.from_input(&input, token_input);
                    try stderr.print("Operator missing required operands.\n{s}\n{s}\n", .{ input.all(), error_string.get() });
                    return 1;
                }
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
        _ = operand_ranges.pop();
        var total_range = operand_ranges.pop().?; // We know length is > 1
        while (operand_ranges.pop()) |range| {
            total_range.end = range.end;
        }
        const error_string = ErrorString.from_input_range(&input, total_range);
        try stderr.print("Unused values.\n{s}\n{s}\n", .{ input.all(), error_string.get() });
        return 1;
    }
    try stdout.print("{d}", .{operands.pop().?});
    return 0;
}
