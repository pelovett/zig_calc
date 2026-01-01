//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const std = @import("std");

const tokenizer = @import("tokenizer.zig");
const parser = @import("parser.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    try stdout.print(">> ", .{});

    while (true) {
        const input = stdin.readUntilDelimiterAlloc(allocator, '\n', 256) catch |err| {
            switch (err) {
                error.EndOfStream => {
                    try stdout.print("\nExiting...\n", .{});
                    std.process.exit(0);
                },
                else => {
                    try stdout.print("Failed to process input: {any}\n", .{err});
                    std.process.exit(1);
                },
            }
        };
        defer allocator.free(input);

        if (input.len == 0) {
            try stdout.print("\nExiting...\n", .{});
            std.process.exit(0);
        } else if (input[0] == 'q') {
            try stdout.print("\nExiting...\n", .{});
            std.process.exit(0);
        }

        const tokens = tokenizer.split(allocator, @constCast(&input)) catch |err| {
            try stdout.print("Failed to tokenize input: {any}\n", .{err});
            std.process.exit(1);
        };
        const syntaxTree = parser.parse(allocator, tokens) catch |err| {
            try stdout.print("Failed to parse syntax: {any}\n", .{err});
            std.process.exit(1);
        };
        const result = parser.compute(syntaxTree) catch |err| {
            try stdout.print("Failed to compute result: {any}\n", .{err});
            std.process.exit(1);
        };
        try stdout.print("{d}\n>> ", .{result});
    }
}

test {
    // To get test library to scan sub-module
    _ = tokenizer;
    _ = parser;
}
