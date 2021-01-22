// SPDX-License-Identifier: MIT
// Copyright (c) 2015-2021 Zig Contributors
// This file is part of [zig](https://ziglang.org/), which is MIT licensed.
// The MIT license requires this copyright notice to be included in all copies
// and substantial portions of the software.
const std = @import("std.zig");
const tokenizer = @import("zig/tokenizer.zig");

pub const Token = tokenizer.Token;
pub const Tokenizer = tokenizer.Tokenizer;
pub const fmtId = @import("zig/fmt.zig").fmtId;
pub const fmtEscapes = @import("zig/fmt.zig").fmtEscapes;
pub const parse = @import("zig/parse.zig").parse;
pub const parseStringLiteral = @import("zig/string_literal.zig").parse;
pub const render = @import("zig/render.zig").render;
pub const ast = @import("zig/ast.zig");
pub const system = @import("zig/system.zig");
pub const CrossTarget = @import("zig/cross_target.zig").CrossTarget;

pub const SrcHash = [16]u8;

/// If the source is small enough, it is used directly as the hash.
/// If it is long, blake3 hash is computed.
pub fn hashSrc(src: []const u8) SrcHash {
    var out: SrcHash = undefined;
    if (src.len <= @typeInfo(SrcHash).Array.len) {
        std.mem.copy(u8, &out, src);
        std.mem.set(u8, out[src.len..], 0);
    } else {
        std.crypto.hash.Blake3.hash(src, &out, .{});
    }
    return out;
}

pub fn findLineColumn(source: []const u8, byte_offset: usize) struct { line: usize, column: usize } {
    var line: usize = 0;
    var column: usize = 0;
    for (source[0..byte_offset]) |byte| {
        switch (byte) {
            '\n' => {
                line += 1;
                column = 0;
            },
            else => {
                column += 1;
            },
        }
    }
    return .{ .line = line, .column = column };
}

pub fn lineDelta(source: []const u8, start: usize, end: usize) isize {
    var line: isize = 0;
    if (end >= start) {
        for (source[start..end]) |byte| switch (byte) {
            '\n' => line += 1,
            else => continue,
        };
    } else {
        for (source[end..start]) |byte| switch (byte) {
            '\n' => line -= 1,
            else => continue,
        };
    }
    return line;
}

pub const BinNameOptions = struct {
    root_name: []const u8,
    target: std.Target,
    output_mode: std.builtin.OutputMode,
    link_mode: ?std.builtin.LinkMode = null,
    object_format: ?std.Target.ObjectFormat = null,
    version: ?std.builtin.Version = null,
};

/// Returns the standard file system basename of a binary generated by the Zig compiler.
pub fn binNameAlloc(allocator: *std.mem.Allocator, options: BinNameOptions) error{OutOfMemory}![]u8 {
    const root_name = options.root_name;
    const target = options.target;
    switch (options.object_format orelse target.getObjectFormat()) {
        .coff, .pe => switch (options.output_mode) {
            .Exe => return std.fmt.allocPrint(allocator, "{s}{s}", .{ root_name, target.exeFileExt() }),
            .Lib => {
                const suffix = switch (options.link_mode orelse .Static) {
                    .Static => ".lib",
                    .Dynamic => ".dll",
                };
                return std.fmt.allocPrint(allocator, "{s}{s}", .{ root_name, suffix });
            },
            .Obj => return std.fmt.allocPrint(allocator, "{s}{s}", .{ root_name, target.oFileExt() }),
        },
        .elf => switch (options.output_mode) {
            .Exe => return allocator.dupe(u8, root_name),
            .Lib => {
                switch (options.link_mode orelse .Static) {
                    .Static => return std.fmt.allocPrint(allocator, "{s}{s}.a", .{
                        target.libPrefix(), root_name,
                    }),
                    .Dynamic => {
                        if (options.version) |ver| {
                            return std.fmt.allocPrint(allocator, "{s}{s}.so.{d}.{d}.{d}", .{
                                target.libPrefix(), root_name, ver.major, ver.minor, ver.patch,
                            });
                        } else {
                            return std.fmt.allocPrint(allocator, "{s}{s}.so", .{
                                target.libPrefix(), root_name,
                            });
                        }
                    },
                }
            },
            .Obj => return std.fmt.allocPrint(allocator, "{s}{s}", .{ root_name, target.oFileExt() }),
        },
        .macho => switch (options.output_mode) {
            .Exe => return allocator.dupe(u8, root_name),
            .Lib => {
                switch (options.link_mode orelse .Static) {
                    .Static => return std.fmt.allocPrint(allocator, "{s}{s}.a", .{
                        target.libPrefix(), root_name,
                    }),
                    .Dynamic => {
                        if (options.version) |ver| {
                            return std.fmt.allocPrint(allocator, "{s}{s}.{d}.{d}.{d}.dylib", .{
                                target.libPrefix(), root_name, ver.major, ver.minor, ver.patch,
                            });
                        } else {
                            return std.fmt.allocPrint(allocator, "{s}{s}.dylib", .{
                                target.libPrefix(), root_name,
                            });
                        }
                    },
                }
                return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ target.libPrefix(), root_name, suffix });
            },
            .Obj => return std.fmt.allocPrint(allocator, "{s}{s}", .{ root_name, target.oFileExt() }),
        },
        .wasm => switch (options.output_mode) {
            .Exe => return std.fmt.allocPrint(allocator, "{s}{s}", .{ root_name, target.exeFileExt() }),
            .Obj => return std.fmt.allocPrint(allocator, "{s}{s}", .{ root_name, target.oFileExt() }),
            .Lib => return std.fmt.allocPrint(allocator, "{s}.wasm", .{root_name}),
        },
        .c => return std.fmt.allocPrint(allocator, "{s}.c", .{root_name}),
        .hex => return std.fmt.allocPrint(allocator, "{s}.ihex", .{root_name}),
        .raw => return std.fmt.allocPrint(allocator, "{s}.bin", .{root_name}),
    }
}

/// Only validates escape sequence characters.
/// Slice must be valid utf8 starting and ending with "'" and exactly one codepoint in between.
pub fn parseCharLiteral(
    slice: []const u8,
    bad_index: *usize, // populated if error.InvalidCharacter is returned
) error{InvalidCharacter}!u32 {
    std.debug.assert(slice.len >= 3 and slice[0] == '\'' and slice[slice.len - 1] == '\'');

    if (slice[1] == '\\') {
        switch (slice[2]) {
            'n' => return '\n',
            'r' => return '\r',
            '\\' => return '\\',
            't' => return '\t',
            '\'' => return '\'',
            '"' => return '"',
            'x' => {
                if (slice.len != 6) {
                    bad_index.* = slice.len - 2;
                    return error.InvalidCharacter;
                }
                var value: u32 = 0;
                for (slice[3..5]) |c, i| {
                    switch (c) {
                        '0'...'9' => {
                            value *= 16;
                            value += c - '0';
                        },
                        'a'...'f' => {
                            value *= 16;
                            value += c - 'a' + 10;
                        },
                        'A'...'F' => {
                            value *= 16;
                            value += c - 'A' + 10;
                        },
                        else => {
                            bad_index.* = 3 + i;
                            return error.InvalidCharacter;
                        },
                    }
                }
                return value;
            },
            'u' => {
                if (slice.len < "'\\u{0}'".len or slice[3] != '{' or slice[slice.len - 2] != '}') {
                    bad_index.* = 2;
                    return error.InvalidCharacter;
                }
                var value: u32 = 0;
                for (slice[4 .. slice.len - 2]) |c, i| {
                    switch (c) {
                        '0'...'9' => {
                            value *= 16;
                            value += c - '0';
                        },
                        'a'...'f' => {
                            value *= 16;
                            value += c - 'a' + 10;
                        },
                        'A'...'F' => {
                            value *= 16;
                            value += c - 'A' + 10;
                        },
                        else => {
                            bad_index.* = 4 + i;
                            return error.InvalidCharacter;
                        },
                    }
                    if (value > 0x10ffff) {
                        bad_index.* = 4 + i;
                        return error.InvalidCharacter;
                    }
                }
                return value;
            },
            else => {
                bad_index.* = 2;
                return error.InvalidCharacter;
            },
        }
    }
    return std.unicode.utf8Decode(slice[1 .. slice.len - 1]) catch unreachable;
}

test "parseCharLiteral" {
    var bad_index: usize = undefined;
    std.testing.expectEqual(try parseCharLiteral("'a'", &bad_index), 'a');
    std.testing.expectEqual(try parseCharLiteral("'ä'", &bad_index), 'ä');
    std.testing.expectEqual(try parseCharLiteral("'\\x00'", &bad_index), 0);
    std.testing.expectEqual(try parseCharLiteral("'\\x4f'", &bad_index), 0x4f);
    std.testing.expectEqual(try parseCharLiteral("'\\x4F'", &bad_index), 0x4f);
    std.testing.expectEqual(try parseCharLiteral("'ぁ'", &bad_index), 0x3041);
    std.testing.expectEqual(try parseCharLiteral("'\\u{0}'", &bad_index), 0);
    std.testing.expectEqual(try parseCharLiteral("'\\u{3041}'", &bad_index), 0x3041);
    std.testing.expectEqual(try parseCharLiteral("'\\u{7f}'", &bad_index), 0x7f);
    std.testing.expectEqual(try parseCharLiteral("'\\u{7FFF}'", &bad_index), 0x7FFF);

    std.testing.expectError(error.InvalidCharacter, parseCharLiteral("'\\x0'", &bad_index));
    std.testing.expectError(error.InvalidCharacter, parseCharLiteral("'\\x000'", &bad_index));
    std.testing.expectError(error.InvalidCharacter, parseCharLiteral("'\\y'", &bad_index));
    std.testing.expectError(error.InvalidCharacter, parseCharLiteral("'\\u'", &bad_index));
    std.testing.expectError(error.InvalidCharacter, parseCharLiteral("'\\uFFFF'", &bad_index));
    std.testing.expectError(error.InvalidCharacter, parseCharLiteral("'\\u{}'", &bad_index));
    std.testing.expectError(error.InvalidCharacter, parseCharLiteral("'\\u{FFFFFF}'", &bad_index));
    std.testing.expectError(error.InvalidCharacter, parseCharLiteral("'\\u{FFFF'", &bad_index));
    std.testing.expectError(error.InvalidCharacter, parseCharLiteral("'\\u{FFFF}x'", &bad_index));
}

test {
    @import("std").testing.refAllDecls(@This());
}
