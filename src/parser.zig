const std = @import("std");
const ArrayList = std.ArrayList;
const testing = std.testing;
const Allocator = std.mem.Allocator;

const tokenizer = @import("tokenizer.zig");
const Operator = tokenizer.Operator;
const Literal = tokenizer.Literal;
const Token = tokenizer.Token;

const TreeNode = struct {
    left: ?*@This(),
    right: ?*@This(),
    this: Token,
};

const ListNode = struct {
    prev: ?*@This(),
    next: ?*@This(),
    this: *TreeNode,
};

const SyntaxParserError = error{
    SyntaxError,
    OpeningWithOperator,
    EndingWithOperator,
    DivisionByZero,
};

// Use pointers to nodes to combine previous and next node under current node
fn collapseNode(
    allocator: Allocator,
    current: *ListNode,
    previous: *ListNode,
    first: **ListNode,
) void {
    current.this.left = previous.this;
    // If we eat the first node, we become the first node
    if (previous == first.*) {
        first.* = current;
    }
    current.this.right = current.next.?.this;

    // Fix ListNode links
    if (previous.prev == null) {
        current.prev = null;
    } else {
        previous.prev.?.next = current;
        current.prev = previous.prev.?;
    }

    const oldNext = current.next;
    if (current.next.?.next == null) {
        current.next = null;
    } else {
        current.next.?.next.?.prev = current;
        current.next = current.next.?.next.?;
    }
    // Both previous and next ListNodes are no longer needed
    allocator.destroy(previous);
    allocator.destroy(oldNext.?);
}

fn opToPrecedence(op: Operator) u8 {
    switch (op) {
        .add, .sub => return 1,
        .div, .mult => return 2,
    }
}

// Parse arraylist of tokens into syntax tree
pub fn parse(allocator: Allocator, input: ArrayList(Token)) !?*TreeNode {
    // First convert tokens into doubly-linked list
    var firstListNode: *ListNode = undefined;
    var prevListNode: *ListNode = undefined;
    for (input.items, 0..) |tok, i| {
        if (i == 0) {
            switch (tok) {
                .lit => {
                    firstListNode = try allocator.create(ListNode);
                    firstListNode.prev = null;
                    firstListNode.next = null;
                    const internalTreeNode = try allocator.create(TreeNode);
                    internalTreeNode.left = null;
                    internalTreeNode.right = null;
                    internalTreeNode.this = tok;
                    firstListNode.this = internalTreeNode;
                },
                // Can't start with an operator
                .op => {
                    return SyntaxParserError.OpeningWithOperator;
                },
            }
            prevListNode = firstListNode;
            continue;
        }

        const curListNode = try allocator.create(ListNode);
        curListNode.prev = prevListNode;
        curListNode.next = null;
        const internalTreeNode = try allocator.create(TreeNode);
        internalTreeNode.left = null;
        internalTreeNode.right = null;
        internalTreeNode.this = tok;
        curListNode.this = internalTreeNode;
        prevListNode.next = curListNode;
        prevListNode = curListNode;
    }

    // TODO check edge cases (1 node, 2 nodes, etc)

    // Continually loop over nodes and try to parse them into a tree
    while (true) {
        if (firstListNode.next == null) {
            break;
        }

        var best: ?*ListNode = null;
        var bestPrecedence: ?u8 = null;
        var cur: ?*ListNode = firstListNode.next;

        // Loop over ListNodes to find highest precedence
        while (cur) |node| {
            sw: switch (node.this.this) {
                .op => |op| {
                    // If tree is already filled out, continue
                    if (node.this.left != null and node.this.right != null) {
                        break :sw;
                    }
                    const precedence = opToPrecedence(op);
                    if (best == null or bestPrecedence.? < precedence) {
                        best = node;
                        bestPrecedence = precedence;
                    }
                },
                // Do nothing for literal nodes
                .lit => {},
            }
            cur = node.next;
        }

        // Must only be literals in List, return
        const toCollapse = best orelse break;

        // If best has no neighbors, then it must be the root of our entire tree
        if (toCollapse.prev == null and toCollapse.next == null) {
            break;
            // If only one neighbor is missing, something is wrong!
        } else if (toCollapse.prev == null or toCollapse.next == null) {
            return SyntaxParserError.SyntaxError;
        }
        collapseNode(allocator, toCollapse, toCollapse.prev.?, &firstListNode);
    }
    const rootNode = firstListNode.this;
    allocator.destroy(firstListNode);
    return rootNode;
}

pub fn deallocParseTree(allocator: Allocator, root: ?*TreeNode) void {
    const node = root orelse return;
    deallocParseTree(allocator, node.left);
    deallocParseTree(allocator, node.right);
    allocator.destroy(node);
}

pub fn compute(root: *const TreeNode) !f64 {
    switch (root.this) {
        .op => |op| {
            const left = try compute(root.left.?);
            const right = try compute(root.right.?);
            switch (op) {
                .add => {
                    return left + right;
                },
                .sub => {
                    return left - right;
                },
                .mult => {
                    return left * right;
                },
                .div => {
                    if (right == 0) {
                        return SyntaxParserError.DivisionByZero;
                    }
                    return left / right;
                },
            }
        },
        .lit => |lit| {
            return lit.value;
        },
    }
}

test "parse simple syntax" {
    var input = ArrayList(Token).init(std.testing.allocator);
    defer input.deinit();
    try input.append(Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } });
    try input.append(Token{ .op = Operator.add });
    try input.append(Token{ .lit = Literal{ .start = 2, .end = 3, .value = 1 } });
    const output = try parse(std.testing.allocator, input) orelse {
        std.log.err("Parser returned null value!\n", .{});
        return SyntaxParserError.SyntaxError;
    };
    defer deallocParseTree(std.testing.allocator, output);

    const expected = &TreeNode{
        .left = @constCast(&TreeNode{
            .left = null,
            .right = null,
            .this = Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } },
        }),
        .this = Token{ .op = Operator.add },
        .right = @constCast(&TreeNode{
            .left = null,
            .right = null,
            .this = Token{ .lit = Literal{ .start = 2, .end = 3, .value = 1 } },
        }),
    };
    try testing.expectEqualDeep(expected, output);
}

test "parse multiop syntax" {
    var input = ArrayList(Token).init(std.testing.allocator);
    defer input.deinit();
    try input.append(Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } });
    try input.append(Token{ .op = Operator.add });
    try input.append(Token{ .lit = Literal{ .start = 2, .end = 3, .value = 1 } });
    try input.append(Token{ .op = Operator.add });
    try input.append(Token{ .lit = Literal{ .start = 4, .end = 5, .value = 1 } });
    const output = try parse(std.testing.allocator, input) orelse {
        std.log.err("Parser returned null value!\n", .{});
        return SyntaxParserError.SyntaxError;
    };
    defer deallocParseTree(std.testing.allocator, output);

    const subtree = &TreeNode{
        .left = @constCast(&TreeNode{
            .left = null,
            .right = null,
            .this = Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } },
        }),
        .this = Token{ .op = Operator.add },
        .right = @constCast(&TreeNode{
            .left = null,
            .right = null,
            .this = Token{ .lit = Literal{ .start = 2, .end = 3, .value = 1 } },
        }),
    };
    const expected = &TreeNode{
        .left = @constCast(subtree),
        .this = Token{ .op = Operator.add },
        .right = @constCast(&TreeNode{
            .left = null,
            .right = null,
            .this = Token{ .lit = Literal{ .start = 4, .end = 5, .value = 1 } },
        }),
    };
    try testing.expectEqualDeep(expected, output);
}

test "parse operator preference" {
    var input = ArrayList(Token).init(std.testing.allocator);
    defer input.deinit();
    try input.append(Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } });
    try input.append(Token{ .op = Operator.add });
    try input.append(Token{ .lit = Literal{ .start = 2, .end = 3, .value = 1 } });
    try input.append(Token{ .op = Operator.mult });
    try input.append(Token{ .lit = Literal{ .start = 4, .end = 5, .value = 1 } });
    const output = try parse(std.testing.allocator, input) orelse {
        std.log.err("Parser returned null value!\n", .{});
        return SyntaxParserError.SyntaxError;
    };
    defer deallocParseTree(std.testing.allocator, output);

    const expected = &TreeNode{
        .left = @constCast(&TreeNode{
            .left = null,
            .right = null,
            .this = Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } },
        }),
        .this = Token{ .op = Operator.add },
        .right = @constCast(&TreeNode{
            .left = @constCast(&TreeNode{
                .left = null,
                .right = null,
                .this = Token{ .lit = Literal{ .start = 2, .end = 3, .value = 1 } },
            }),
            .this = Token{ .op = Operator.mult },
            .right = @constCast(&TreeNode{
                .left = null,
                .right = null,
                .this = Token{ .lit = Literal{ .start = 4, .end = 5, .value = 1 } },
            }),
        }),
    };
    try testing.expectEqualDeep(expected, output);
}

test "parse double nested preference" {
    var input = ArrayList(Token).init(std.testing.allocator);
    defer input.deinit();
    try input.append(Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } });
    try input.append(Token{ .op = Operator.mult });
    try input.append(Token{ .lit = Literal{ .start = 2, .end = 3, .value = 1 } });
    try input.append(Token{ .op = Operator.add });
    try input.append(Token{ .lit = Literal{ .start = 4, .end = 5, .value = 1 } });
    try input.append(Token{ .op = Operator.mult });
    try input.append(Token{ .lit = Literal{ .start = 6, .end = 7, .value = 1 } });
    const output = try parse(std.testing.allocator, input) orelse {
        std.log.err("Parser returned null value!\n", .{});
        return SyntaxParserError.SyntaxError;
    };
    defer deallocParseTree(std.testing.allocator, output);

    const expected = &TreeNode{
        .left = @constCast(&TreeNode{
            .left = @constCast(&TreeNode{
                .left = null,
                .right = null,
                .this = Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } },
            }),
            .this = Token{ .op = Operator.mult },
            .right = @constCast(&TreeNode{
                .left = null,
                .right = null,
                .this = Token{ .lit = Literal{ .start = 2, .end = 3, .value = 1 } },
            }),
        }),
        .this = Token{ .op = Operator.add },
        .right = @constCast(&TreeNode{
            .left = @constCast(&TreeNode{
                .left = null,
                .right = null,
                .this = Token{ .lit = Literal{ .start = 4, .end = 5, .value = 1 } },
            }),
            .this = Token{ .op = Operator.mult },
            .right = @constCast(&TreeNode{
                .left = null,
                .right = null,
                .this = Token{ .lit = Literal{ .start = 6, .end = 7, .value = 1 } },
            }),
        }),
    };
    try testing.expectEqualDeep(expected, output);
}

test "parse mult in tha middle" {
    var input = ArrayList(Token).init(std.testing.allocator);
    defer input.deinit();
    try input.append(Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } });
    try input.append(Token{ .op = Operator.add });
    try input.append(Token{ .lit = Literal{ .start = 2, .end = 3, .value = 1 } });
    try input.append(Token{ .op = Operator.mult });
    try input.append(Token{ .lit = Literal{ .start = 4, .end = 5, .value = 1 } });
    try input.append(Token{ .op = Operator.add });
    try input.append(Token{ .lit = Literal{ .start = 6, .end = 7, .value = 1 } });
    const output = try parse(std.testing.allocator, input) orelse {
        std.log.err("Parser returned null value!\n", .{});
        return SyntaxParserError.SyntaxError;
    };
    defer deallocParseTree(std.testing.allocator, output);

    const expected = &TreeNode{
        .left = @constCast(&TreeNode{
            .left = @constCast(&TreeNode{
                .left = null,
                .right = null,
                .this = Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } },
            }),
            .this = Token{ .op = Operator.add },
            .right = @constCast(&TreeNode{
                .left = @constCast(&TreeNode{
                    .left = null,
                    .right = null,
                    .this = Token{ .lit = Literal{ .start = 2, .end = 3, .value = 1 } },
                }),
                .this = Token{ .op = Operator.mult },
                .right = @constCast(&TreeNode{
                    .left = null,
                    .right = null,
                    .this = Token{ .lit = Literal{ .start = 4, .end = 5, .value = 1 } },
                }),
            }),
        }),
        .this = Token{ .op = Operator.add },
        .right = @constCast(&TreeNode{
            .left = null,
            .right = null,
            .this = Token{ .lit = Literal{ .start = 6, .end = 7, .value = 1 } },
        }),
    };
    try testing.expectEqualDeep(expected, output);
}

test "compute simple syntax" {
    const input = &TreeNode{
        .left = @constCast(&TreeNode{
            .left = null,
            .right = null,
            .this = Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } },
        }),
        .this = Token{ .op = Operator.add },
        .right = @constCast(&TreeNode{
            .left = null,
            .right = null,
            .this = Token{ .lit = Literal{ .start = 2, .end = 3, .value = 1 } },
        }),
    };
    try testing.expectEqual(2, compute(input));
}

test "compute complex syntax" {
    const input = &TreeNode{
        .left = @constCast(&TreeNode{
            .left = @constCast(&TreeNode{
                .left = null,
                .right = null,
                .this = Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } },
            }),
            .this = Token{ .op = Operator.add },
            .right = @constCast(&TreeNode{
                .left = @constCast(&TreeNode{
                    .left = null,
                    .right = null,
                    .this = Token{ .lit = Literal{ .start = 2, .end = 3, .value = 2 } },
                }),
                .this = Token{ .op = Operator.mult },
                .right = @constCast(&TreeNode{
                    .left = null,
                    .right = null,
                    .this = Token{ .lit = Literal{ .start = 4, .end = 5, .value = 4 } },
                }),
            }),
        }),
        .this = Token{ .op = Operator.add },
        .right = @constCast(&TreeNode{
            .left = null,
            .right = null,
            .this = Token{ .lit = Literal{ .start = 6, .end = 7, .value = 1 } },
        }),
    };
    try testing.expectEqual(10, compute(input));
}

test "detect division by zero" {
    const input = &TreeNode{
        .left = @constCast(&TreeNode{
            .left = null,
            .right = null,
            .this = Token{ .lit = Literal{ .start = 0, .end = 1, .value = 1 } },
        }),
        .this = Token{ .op = Operator.div },
        .right = @constCast(&TreeNode{
            .left = null,
            .right = null,
            .this = Token{ .lit = Literal{ .start = 2, .end = 3, .value = 0 } },
        }),
    };
    try testing.expectError(SyntaxParserError.DivisionByZero, compute(input));
}
