const std = @import("std");

const InputStore = struct {
    /// Structure for storing command-line inputs for good error output.
    ///  Automatically adds spaces between arguments.
    const StoreSlice = struct {
        head: u24, // u16, but we'll just use the extra space. Only 1 byte wasted as opposed to 7 with Stack(Token).
        len: u8,
    };

    const limit_head = std.math.maxInt(@FieldType(StoreSlice, "head"));
    const limit_string = std.math.maxInt(@FieldType(StoreSlice, "len"));
    const capacity = 256;
    const string_capacity = capacity * 4;

    strings: [*]u8 = undefined,
    slices: [*]StoreSlice = undefined,
    head: usize = 0,
    len: usize = 0,

    fn init(allocator: std.mem.Allocator) !InputStore {
        return .{ .strings = (try allocator.alloc(u8, string_capacity)).ptr, .slices = (try allocator.alloc(StoreSlice, capacity)).ptr, .head = 0, .len = 0 };
    }

    fn deinit(self: *InputStore, allocator: std.mem.Allocator) void {
        allocator.free(self.strings[0..string_capacity]);
        allocator.free(self.slices[0..capacity]);
        self.head = 0;
        self.len = 0;
    }

    fn push(self: *InputStore, value: []const u8) error{ full, out_of_range }!void {
        if (self.head + value.len > limit_head or value.len > limit_string) return error.out_of_range;
        if (self.len == capacity or self.head + value.len > string_capacity) return error.full;
        if (self.len != 0) {
            self.strings[self.head] = ' ';
            self.head += 1;
        }
        std.mem.copyForwards(u8, self.strings[self.head..string_capacity], value);
        self.slices[self.len] = .{ .head = @truncate(self.head), .len = @truncate(value.len) };
        self.head += value.len;
        self.len += 1;
    }

    fn get(self: InputStore, index: usize) []const u8 {
        const slice = self.slices[index];
        return self.strings[slice.head .. slice.head + slice.len];
    }

    fn all(self: InputStore) []const u8 {
        return self.strings[0..self.head];
    }
};

const ErrorString = struct {
    const capacity = 1016;
    data: [capacity]u8 = undefined,
    len: usize = 0,

    fn init(store: InputStore, index: usize) ErrorString {
        var self: ErrorString = .{};
        const item = store.slices[index];
        @memset(self.data[0..item.head], ' ');
        @memset(self.data[item.head .. item.head + item.len], '^');
        self.len = item.head + item.len;
        return self;
    }

    fn get(self: ErrorString) []const u8 {
        return self.data[0..self.len];
    }
};

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

const Operator = enum { add, sub, mul, div, pow };

const TokenStack = struct {
    // This can probably be made into a generic, but it's fine to stay like this.
    const Type = enum(u8) { operand, operator };
    const Data = union { operand: f64, operator: Operator };
    const Token = union(Type) { operand: f64, operator: Operator };

    const capacity = 256;

    tokens: [capacity]Data = undefined,
    types: [capacity]Type = undefined,
    len: usize = 0,

    fn init() TokenStack {
        return .{};
    }

    fn push(self: *TokenStack, value: Token) error{full}!void {
        if (self.len == capacity) return error.full;
        switch (value) {
            .operand => |operand| {
                self.tokens[self.len] = .{ .operand = operand };
                self.types[self.len] = .operand;
                self.len += 1;
            },
            .operator => |operator| {
                self.tokens[self.len] = .{ .operator = operator };
                self.types[self.len] = .operator;
                self.len += 1;
            },
        }
    }

    fn pop(self: *TokenStack) ?Token {
        if (self.len == 0) return null;
        self.len -= 1;
        return switch (self.types[self.len]) {
            .operand => .{ .operand = self.tokens[self.len].operand },
            .operator => .{ .operator = self.tokens[self.len].operator },
        };
    }
};

pub fn main() !u8 {
    // How do we add good error output?
    //  We need to track where the token was in the command input and how long it was.
    //  Strip the path off the command name.
    //  Since we will strip the path, it doesn't help us to have access to the original arg string anyway.
    //  Print help text.
    //  Try to determine if the input was meant to be an operand or operator. <- this probably requires an AST.
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var dba = std.heap.DebugAllocator(.{}){};
    const debug_allocator = dba.allocator();

    //const type_in_question = Token;
    //try stdout.print("Size of {s}: {}\n", .{ @typeName(type_in_question), @sizeOf(type_in_question) });

    var input = try InputStore.init(debug_allocator);
    defer input.deinit(debug_allocator);

    var tokens = TokenStack.init();
    {
        var arg_buffer: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&arg_buffer);
        const allocator = fba.allocator();
        var args = try std.process.argsWithAllocator(allocator);
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

    for (1..input.len) |i| {
        const arg = input.get(i);
        const operand: ?f64 = std.fmt.parseFloat(f64, arg) catch null;
        // Iterate over the names of the Operator enum and see if the input matches any.
        const operator: ?Operator = for (std.meta.tags(Operator)) |op| {
            if (std.mem.eql(u8, @tagName(op), arg)) break op;
        } else null;

        if (operand == null and operator == null) {
            const error_string = ErrorString.init(input, i);
            try stderr.print("Invalid operator or operand.\n{s}\n{s}\n", .{ input.all(), error_string.get() });
            return 1;
        }

        tokens.push(if (operand != null) .{ .operand = operand.? } else .{ .operator = operator.? }) catch {
            try stderr.print("Exceeded maximum count of operands and operators.\n", .{});
            return 1;
        };
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

    var operands = Stack(f64).init();
    while (tokens.pop()) |token| {
        switch (token) {
            .operand => |operand| {
                operands.push(operand) catch {
                    try stderr.print("Exceeded maximum operand count.\n", .{});
                    return 1;
                };
            },
            .operator => |operator| {
                // Check length here to avoid duplicated checking below.
                if (operands.len < 2) {
                    try stderr.print("Operator missing required operands.\n", .{});
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
            },
        }
    }

    if (operands.len < 1) {
        try stdout.print("nil", .{});
        return 1;
    }
    try stdout.print("{d}", .{operands.pop().?});
    return 0;
}
