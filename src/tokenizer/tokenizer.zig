const std = @import("std");
const ArrayList = std.ArrayList;
const testing = std.testing;
const Allocator = std.mem.Allocator;

const Operator = enum {
    add,
    sub,
    mult,
    div,
};

const Literal = struct {
    start: usize,
    end: usize,
    value: f64,
};

const Token = union(enum) {
    op: Operator,
    lit: Literal,
};

const TokenizerError = error{
    UnexpectedCharacter,
};

pub fn split(allocator: Allocator, input: *const []const u8) !ArrayList(Token) {
    var output = ArrayList(Token).init(allocator);
    var tokStart: ?usize = null;
    var tokEnd: ?usize = null;
    var seenDecimal = false;

    for (input.*, 0..) |char, i| {
        if (char == '+' or char == '/' or char == '*') {
            // This will be a new token, so close our old one
            if (tokStart != null) {
                try output.append(Token{ .lit = Literal{
                    .start = tokStart.?,
                    .end = tokEnd.?,
                    .value = try std.fmt.parseFloat(f64, input.*[tokStart.?..tokEnd.?]),
                } });
                tokStart = null;
                tokEnd = null;
                seenDecimal = false;
            }
            switch (char) {
                '+' => try output.append(Token{ .op = Operator.add }),
                '/' => try output.append(Token{ .op = Operator.div }),
                '*' => try output.append(Token{ .op = Operator.mult }),
                else => unreachable,
            }
        } else if (char == '-') {
            // If previous token is null or operator, then optimistically try to start a literal
            if ((output.items.len == 0 and tokStart == null) or (output.items.len != 0 and output.items[output.items.len - 1] == .op)) {
                tokStart = i;
                tokEnd = i + 1;
            } else {
                // Must be subtraction operator
                // This will be a new token, so close our old one
                if (tokStart != null) {
                    try output.append(Token{ .lit = Literal{ .start = tokStart.?, .end = tokEnd.?, .value = try std.fmt.parseFloat(f64, input.*[tokStart.?..tokEnd.?]) } });
                    tokStart = null;
                    tokEnd = null;
                    seenDecimal = false;
                }
                try output.append(Token{ .op = Operator.sub });
            }
        } else if (std.ascii.isWhitespace(char)) {
            // Check if we're inside of a token
            if (tokStart != null) {
                try output.append(Token{ .lit = Literal{ .start = tokStart.?, .end = tokEnd.?, .value = try std.fmt.parseFloat(f64, input.*[tokStart.?..tokEnd.?]) } });
                tokStart = null;
                tokEnd = null;
            }
        } else if (std.ascii.isDigit(char)) {
            // If we haven't started our token span, then i is the start
            if (tokStart == null) {
                tokStart = i;
                tokEnd = i + 1;
            } else {
                // Otherwise do nothing until we terminate
                tokEnd.? += 1;
            }
        } else if (char == '.') {
            // This is the beginning of a decimal value
            if (tokStart == null) {
                tokStart = i;
                tokEnd = i + 1;
                seenDecimal = true;
            } else {
                // Can only have one decimal per literal
                if (seenDecimal) {
                    return TokenizerError.UnexpectedCharacter;
                }
                seenDecimal = true;
                tokEnd.? += 1;
            }
        } else {
            // Anything other than characters caught above is an error
            return TokenizerError.UnexpectedCharacter;
        }
    }
    // Check if we haven't closed the last literal
    if (tokStart != null) {
        try output.append(Token{ .lit = Literal{ .start = tokStart.?, .end = tokEnd.?, .value = try std.fmt.parseFloat(f64, input.*[tokStart.?..tokEnd.?]) } });
    }
    return output;
}

test "tokenize simple add" {
    var input: []const u8 = "1+1";
    const output = try split(std.testing.allocator, &input);
    defer output.deinit();

    var expectedArray = [_]Token{ Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } }, Token{ .op = Operator.add }, Token{ .lit = Literal{ .start = 2, .end = 3, .value = 1 } } };
    const expected: []Token = expectedArray[0..];

    try testing.expectEqual(expected.len, output.items.len);
    for (expectedArray, 0..) |tok, i| {
        try testing.expectEqual(tok, output.items[i]);
    }
}

test "tokenize add with spaces" {
    var input: []const u8 = " 1 +  1 ";
    const output = try split(std.testing.allocator, &input);
    defer output.deinit();

    var expectedArray = [_]Token{ Token{ .lit = Literal{ .start = 1, .end = 2, .value = 1 } }, Token{ .op = Operator.add }, Token{ .lit = Literal{ .start = 6, .end = 7, .value = 1 } } };
    const expected: []Token = expectedArray[0..];

    try testing.expectEqual(expected.len, output.items.len);
    for (expectedArray, 0..) |tok, i| {
        try testing.expectEqual(tok, output.items[i]);
    }
}

test "tokenize long digits" {
    var input: []const u8 = "123+123456";
    const output = try split(std.testing.allocator, &input);
    defer output.deinit();

    var expectedArray = [_]Token{ Token{ .lit = Literal{ .start = 0, .end = 3, .value = 123 } }, Token{ .op = Operator.add }, Token{ .lit = Literal{ .start = 4, .end = 10, .value = 123456 } } };
    const expected: []Token = expectedArray[0..];

    try testing.expectEqual(expected.len, output.items.len);
    for (expectedArray, 0..) |tok, i| {
        try testing.expectEqual(tok, output.items[i]);
    }
}

test "tokenize simple sub" {
    var input: []const u8 = "1-1";
    const output = try split(std.testing.allocator, &input);
    defer output.deinit();

    var expectedArray = [_]Token{ Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } }, Token{ .op = Operator.sub }, Token{ .lit = Literal{ .start = 2, .end = 3, .value = 1 } } };
    const expected: []Token = expectedArray[0..];

    try testing.expectEqual(expected.len, output.items.len);
    for (expectedArray, 0..) |tok, i| {
        try testing.expectEqual(tok, output.items[i]);
    }
}

test "tokenize add leading negative num" {
    var input: []const u8 = "-1+1";
    const output = try split(std.testing.allocator, &input);
    defer output.deinit();

    var expectedArray = [_]Token{ Token{ .lit = Literal{ .start = 0, .end = 2, .value = -1 } }, Token{ .op = Operator.add }, Token{ .lit = Literal{ .start = 3, .end = 4, .value = 1 } } };
    const expected: []Token = expectedArray[0..];

    try testing.expectEqual(expected.len, output.items.len);
    for (expectedArray, 0..) |tok, i| {
        try testing.expectEqual(tok, output.items[i]);
    }
}

test "tokenize negative after operator" {
    var input: []const u8 = "1+-1";
    const output = try split(std.testing.allocator, &input);
    defer output.deinit();

    var expectedArray = [_]Token{ Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } }, Token{ .op = Operator.add }, Token{ .lit = Literal{ .start = 2, .end = 4, .value = -1 } } };
    const expected: []Token = expectedArray[0..];

    try testing.expectEqual(expected.len, output.items.len);
    for (expectedArray, 0..) |tok, i| {
        try testing.expectEqual(tok, output.items[i]);
    }
}

test "tokenize simple mult" {
    var input: []const u8 = "1*1";
    const output = try split(std.testing.allocator, &input);
    defer output.deinit();

    var expectedArray = [_]Token{ Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } }, Token{ .op = Operator.mult }, Token{ .lit = Literal{ .start = 2, .end = 3, .value = 1 } } };
    const expected: []Token = expectedArray[0..];

    try testing.expectEqual(expected.len, output.items.len);
    for (expectedArray, 0..) |tok, i| {
        try testing.expectEqual(tok, output.items[i]);
    }
}

test "tokenize simple div" {
    var input: []const u8 = "1/1";
    const output = try split(std.testing.allocator, &input);
    defer output.deinit();

    var expectedArray = [_]Token{ Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } }, Token{ .op = Operator.div }, Token{ .lit = Literal{ .start = 2, .end = 3, .value = 1 } } };
    const expected: []Token = expectedArray[0..];

    try testing.expectEqual(expected.len, output.items.len);
    for (expectedArray, 0..) |tok, i| {
        try testing.expectEqual(tok, output.items[i]);
    }
}

test "tokenize simple fraction" {
    var input: []const u8 = "1.123+1";
    const output = try split(std.testing.allocator, &input);
    defer output.deinit();

    var expectedArray = [_]Token{ Token{ .lit = Literal{ .start = 0, .end = 5, .value = 1.123 } }, Token{ .op = Operator.add }, Token{ .lit = Literal{ .start = 6, .end = 7, .value = 1 } } };
    const expected: []Token = expectedArray[0..];

    try testing.expectEqual(expected.len, output.items.len);
    for (expectedArray, 0..) |tok, i| {
        try testing.expectEqual(tok, output.items[i]);
    }
}
test "tokenize leading fraction" {
    var input: []const u8 = ".123+1";
    const output = try split(std.testing.allocator, &input);
    defer output.deinit();

    var expectedArray = [_]Token{ Token{ .lit = Literal{ .start = 0, .end = 4, .value = 0.123 } }, Token{ .op = Operator.add }, Token{ .lit = Literal{ .start = 5, .end = 6, .value = 1 } } };
    const expected: []Token = expectedArray[0..];

    try testing.expectEqual(expected.len, output.items.len);
    for (expectedArray, 0..) |tok, i| {
        try testing.expectEqual(tok, output.items[i]);
    }
}

test "tokenize negative fraction" {
    var input: []const u8 = "-1.123+1";
    const output = try split(std.testing.allocator, &input);
    defer output.deinit();

    var expectedArray = [_]Token{ Token{ .lit = Literal{ .start = 0, .end = 6, .value = -1.123 } }, Token{ .op = Operator.add }, Token{ .lit = Literal{ .start = 7, .end = 8, .value = 1 } } };
    const expected: []Token = expectedArray[0..];

    try testing.expectEqual(expected.len, output.items.len);
    for (expectedArray, 0..) |tok, i| {
        try testing.expectEqual(tok, output.items[i]);
    }
}

test "catch double fraction error" {
    var input: []const u8 = "1.12.3";
    const output = split(std.testing.allocator, &input);

    try testing.expectError(TokenizerError.UnexpectedCharacter, output);
}

test "catch double leading fraction error" {
    var input: []const u8 = "..123";
    const output = split(std.testing.allocator, &input);

    try testing.expectError(TokenizerError.UnexpectedCharacter, output);
}
