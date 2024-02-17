pub const Fde = struct {
    /// Includes 4byte size cell.
    offset: usize,
    size: usize,
    cie_index: u32,
    rel_index: u32 = 0,
    rel_num: u32 = 0,
    input_section_index: u32 = 0,
    file_index: u32 = 0,
    alive: bool = true,
    /// Includes 4byte size cell.
    out_offset: u64 = 0,

    pub fn address(fde: Fde, elf_file: *Elf) u64 {
        const base: u64 = if (elf_file.eh_frame_section_index) |shndx|
            elf_file.shdrs.items[shndx].sh_addr
        else
            0;
        return base + fde.out_offset;
    }

    pub fn data(fde: Fde, elf_file: *Elf) []u8 {
        const object = elf_file.file(fde.file_index).?.object;
        return object.eh_frame_data.items[fde.offset..][0..fde.calcSize()];
    }

    pub fn cie(fde: Fde, elf_file: *Elf) Cie {
        const object = elf_file.file(fde.file_index).?.object;
        return object.cies.items[fde.cie_index];
    }

    pub fn ciePointer(fde: Fde, elf_file: *Elf) u32 {
        const fde_data = fde.data(elf_file);
        return std.mem.readInt(u32, fde_data[4..8], .little);
    }

    pub fn calcSize(fde: Fde) usize {
        return fde.size + 4;
    }

    pub fn atom(fde: Fde, elf_file: *Elf) *Atom {
        const object = elf_file.file(fde.file_index).?.object;
        const rel = fde.relocs(elf_file)[0];
        const sym = object.symtab.items[rel.r_sym()];
        const atom_index = object.atoms.items[sym.st_shndx];
        return elf_file.atom(atom_index).?;
    }

    pub fn relocs(fde: Fde, elf_file: *Elf) []align(1) const elf.Elf64_Rela {
        const object = elf_file.file(fde.file_index).?.object;
        return object.relocs.items[fde.rel_index..][0..fde.rel_num];
    }

    pub fn format(
        fde: Fde,
        comptime unused_fmt_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fde;
        _ = unused_fmt_string;
        _ = options;
        _ = writer;
        @compileError("do not format FDEs directly");
    }

    pub fn fmt(fde: Fde, elf_file: *Elf) std.fmt.Formatter(format2) {
        return .{ .data = .{
            .fde = fde,
            .elf_file = elf_file,
        } };
    }

    const FdeFormatContext = struct {
        fde: Fde,
        elf_file: *Elf,
    };

    fn format2(
        ctx: FdeFormatContext,
        comptime unused_fmt_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = unused_fmt_string;
        _ = options;
        const fde = ctx.fde;
        const elf_file = ctx.elf_file;
        const base_addr = fde.address(elf_file);
        const atom_name = fde.atom(elf_file).name(elf_file);
        try writer.print("@{x} : size({x}) : cie({d}) : {s}", .{
            base_addr + fde.out_offset,
            fde.calcSize(),
            fde.cie_index,
            atom_name,
        });
        if (!fde.alive) try writer.writeAll(" : [*]");
    }
};

pub const Cie = struct {
    /// Includes 4byte size cell.
    offset: usize,
    size: usize,
    rel_index: u32 = 0,
    rel_num: u32 = 0,
    input_section_index: u32 = 0,
    file_index: u32 = 0,
    /// Includes 4byte size cell.
    out_offset: u64 = 0,
    alive: bool = false,

    pub fn address(cie: Cie, elf_file: *Elf) u64 {
        const base: u64 = if (elf_file.eh_frame_section_index) |shndx|
            elf_file.shdrs.items[shndx].sh_addr
        else
            0;
        return base + cie.out_offset;
    }

    pub fn data(cie: Cie, elf_file: *Elf) []u8 {
        const object = elf_file.file(cie.file_index).?.object;
        return object.eh_frame_data.items[cie.offset..][0..cie.calcSize()];
    }

    pub fn calcSize(cie: Cie) usize {
        return cie.size + 4;
    }

    pub fn relocs(cie: Cie, elf_file: *Elf) []align(1) const elf.Elf64_Rela {
        const object = elf_file.file(cie.file_index).?.object;
        return object.relocs.items[cie.rel_index..][0..cie.rel_num];
    }

    pub fn eql(cie: Cie, other: Cie, elf_file: *Elf) bool {
        if (!std.mem.eql(u8, cie.data(elf_file), other.data(elf_file))) return false;

        const cie_relocs = cie.relocs(elf_file);
        const other_relocs = other.relocs(elf_file);
        if (cie_relocs.len != other_relocs.len) return false;

        for (cie_relocs, other_relocs) |cie_rel, other_rel| {
            if (cie_rel.r_offset - cie.offset != other_rel.r_offset - other.offset) return false;
            if (cie_rel.r_type() != other_rel.r_type()) return false;
            if (cie_rel.r_addend != other_rel.r_addend) return false;

            const cie_object = elf_file.file(cie.file_index).?.object;
            const other_object = elf_file.file(other.file_index).?.object;
            const cie_sym = cie_object.symbols.items[cie_rel.r_sym()];
            const other_sym = other_object.symbols.items[other_rel.r_sym()];
            if (!std.mem.eql(u8, std.mem.asBytes(&cie_sym), std.mem.asBytes(&other_sym))) return false;
        }
        return true;
    }

    pub fn format(
        cie: Cie,
        comptime unused_fmt_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = cie;
        _ = unused_fmt_string;
        _ = options;
        _ = writer;
        @compileError("do not format CIEs directly");
    }

    pub fn fmt(cie: Cie, elf_file: *Elf) std.fmt.Formatter(format2) {
        return .{ .data = .{
            .cie = cie,
            .elf_file = elf_file,
        } };
    }

    const CieFormatContext = struct {
        cie: Cie,
        elf_file: *Elf,
    };

    fn format2(
        ctx: CieFormatContext,
        comptime unused_fmt_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = unused_fmt_string;
        _ = options;
        const cie = ctx.cie;
        const elf_file = ctx.elf_file;
        const base_addr = cie.address(elf_file);
        try writer.print("@{x} : size({x})", .{
            base_addr + cie.out_offset,
            cie.calcSize(),
        });
        if (!cie.alive) try writer.writeAll(" : [*]");
    }
};

pub const Iterator = struct {
    data: []const u8,
    pos: usize = 0,

    pub const Record = struct {
        tag: enum { fde, cie },
        offset: usize,
        size: usize,
    };

    pub fn next(it: *Iterator) !?Record {
        if (it.pos >= it.data.len) return null;

        var stream = std.io.fixedBufferStream(it.data[it.pos..]);
        const reader = stream.reader();

        const size = try reader.readInt(u32, .little);
        if (size == 0xFFFFFFFF) @panic("TODO");

        const id = try reader.readInt(u32, .little);
        const record = Record{
            .tag = if (id == 0) .cie else .fde,
            .offset = it.pos,
            .size = size,
        };
        it.pos += size + 4;

        return record;
    }
};

pub fn calcEhFrameSize(elf_file: *Elf) !usize {
    const comp = elf_file.base.comp;
    const gpa = comp.gpa;

    var offset: usize = 0;

    var cies = std.ArrayList(Cie).init(gpa);
    defer cies.deinit();

    for (elf_file.objects.items) |index| {
        const object = elf_file.file(index).?.object;

        outer: for (object.cies.items) |*cie| {
            for (cies.items) |other| {
                if (other.eql(cie.*, elf_file)) {
                    // We already have a CIE record that has the exact same contents, so instead of
                    // duplicating them, we mark this one dead and set its output offset to be
                    // equal to that of the alive record. This way, we won't have to rewrite
                    // Fde.cie_index field when committing the records to file.
                    cie.out_offset = other.out_offset;
                    continue :outer;
                }
            }
            cie.alive = true;
            cie.out_offset = offset;
            offset += cie.calcSize();
            try cies.append(cie.*);
        }
    }

    for (elf_file.objects.items) |index| {
        const object = elf_file.file(index).?.object;
        for (object.fdes.items) |*fde| {
            if (!fde.alive) continue;
            fde.out_offset = offset;
            offset += fde.calcSize();
        }
    }

    if (!elf_file.base.isRelocatable()) {
        offset += 4; // NULL terminator
    }

    return offset;
}

pub fn calcEhFrameHdrSize(elf_file: *Elf) usize {
    var count: usize = 0;
    for (elf_file.objects.items) |index| {
        for (elf_file.file(index).?.object.fdes.items) |fde| {
            if (!fde.alive) continue;
            count += 1;
        }
    }
    return eh_frame_hdr_header_size + count * 8;
}

pub fn calcEhFrameRelocs(elf_file: *Elf) usize {
    var count: usize = 0;
    for (elf_file.objects.items) |index| {
        const object = elf_file.file(index).?.object;
        for (object.cies.items) |cie| {
            if (!cie.alive) continue;
            count += cie.relocs(elf_file).len;
        }
        for (object.fdes.items) |fde| {
            if (!fde.alive) continue;
            count += fde.relocs(elf_file).len;
        }
    }
    return count;
}

fn resolveReloc(rec: anytype, sym: *const Symbol, rel: elf.Elf64_Rela, elf_file: *Elf, contents: []u8) !void {
    const cpu_arch = elf_file.getTarget().cpu.arch;
    const offset = std.math.cast(usize, rel.r_offset - rec.offset) orelse return error.Overflow;
    const P = math.cast(i64, rec.address(elf_file) + offset) orelse return error.Overflow;
    const S = math.cast(i64, sym.address(.{}, elf_file)) orelse return error.Overflow;
    const A = rel.r_addend;

    relocs_log.debug("  {s}: {x}: [{x} => {x}] ({s})", .{
        relocation.fmtRelocType(rel.r_type(), cpu_arch),
        offset,
        P,
        S + A,
        sym.name(elf_file),
    });

    switch (cpu_arch) {
        .x86_64 => x86_64.resolveReloc(rel, P, S + A, contents[offset..]),
        else => return error.UnsupportedCpuArch,
    }
}

pub fn writeEhFrame(elf_file: *Elf, writer: anytype) !void {
    relocs_log.debug("{x}: .eh_frame", .{elf_file.shdrs.items[elf_file.eh_frame_section_index.?].sh_addr});

    for (elf_file.objects.items) |index| {
        const object = elf_file.file(index).?.object;

        for (object.cies.items) |cie| {
            if (!cie.alive) continue;

            const contents = cie.data(elf_file);

            for (cie.relocs(elf_file)) |rel| {
                const sym = elf_file.symbol(object.symbols.items[rel.r_sym()]);
                try resolveReloc(cie, sym, rel, elf_file, contents);
            }

            try writer.writeAll(contents);
        }
    }

    for (elf_file.objects.items) |index| {
        const object = elf_file.file(index).?.object;

        for (object.fdes.items) |fde| {
            if (!fde.alive) continue;

            const contents = fde.data(elf_file);

            std.mem.writeInt(
                i32,
                contents[4..8],
                @truncate(@as(i64, @intCast(fde.out_offset + 4)) - @as(i64, @intCast(fde.cie(elf_file).out_offset))),
                .little,
            );

            for (fde.relocs(elf_file)) |rel| {
                const sym = elf_file.symbol(object.symbols.items[rel.r_sym()]);
                try resolveReloc(fde, sym, rel, elf_file, contents);
            }

            try writer.writeAll(contents);
        }
    }

    try writer.writeInt(u32, 0, .little);
}

pub fn writeEhFrameObject(elf_file: *Elf, writer: anytype) !void {
    for (elf_file.objects.items) |index| {
        const object = elf_file.file(index).?.object;

        for (object.cies.items) |cie| {
            if (!cie.alive) continue;
            try writer.writeAll(cie.data(elf_file));
        }
    }

    for (elf_file.objects.items) |index| {
        const object = elf_file.file(index).?.object;

        for (object.fdes.items) |fde| {
            if (!fde.alive) continue;

            const contents = fde.data(elf_file);

            std.mem.writeInt(
                i32,
                contents[4..8],
                @truncate(@as(i64, @intCast(fde.out_offset + 4)) - @as(i64, @intCast(fde.cie(elf_file).out_offset))),
                .little,
            );

            try writer.writeAll(contents);
        }
    }
}

fn emitReloc(elf_file: *Elf, rec: anytype, sym: *const Symbol, rel: elf.Elf64_Rela) elf.Elf64_Rela {
    const cpu_arch = elf_file.getTarget().cpu.arch;
    const r_offset = rec.address(elf_file) + rel.r_offset - rec.offset;
    const r_type = rel.r_type();
    var r_addend = rel.r_addend;
    var r_sym: u32 = 0;
    switch (sym.type(elf_file)) {
        elf.STT_SECTION => {
            r_addend += @intCast(sym.address(.{}, elf_file));
            r_sym = elf_file.sectionSymbolOutputSymtabIndex(sym.outputShndx().?);
        },
        else => {
            r_sym = sym.outputSymtabIndex(elf_file) orelse 0;
        },
    }

    relocs_log.debug("  {s}: [{x} => {d}({s})] + {x}", .{
        relocation.fmtRelocType(r_type, cpu_arch),
        r_offset,
        r_sym,
        sym.name(elf_file),
        r_addend,
    });

    return .{
        .r_offset = r_offset,
        .r_addend = r_addend,
        .r_info = (@as(u64, @intCast(r_sym)) << 32) | r_type,
    };
}

pub fn writeEhFrameRelocs(elf_file: *Elf, writer: anytype) !void {
    relocs_log.debug("{x}: .eh_frame", .{elf_file.shdrs.items[elf_file.eh_frame_section_index.?].sh_addr});

    for (elf_file.objects.items) |index| {
        const object = elf_file.file(index).?.object;

        for (object.cies.items) |cie| {
            if (!cie.alive) continue;
            for (cie.relocs(elf_file)) |rel| {
                const sym = elf_file.symbol(object.symbols.items[rel.r_sym()]);
                const out_rel = emitReloc(elf_file, cie, sym, rel);
                try writer.writeStruct(out_rel);
            }
        }

        for (object.fdes.items) |fde| {
            if (!fde.alive) continue;
            for (fde.relocs(elf_file)) |rel| {
                const sym = elf_file.symbol(object.symbols.items[rel.r_sym()]);
                const out_rel = emitReloc(elf_file, fde, sym, rel);
                try writer.writeStruct(out_rel);
            }
        }
    }
}

pub fn writeEhFrameHdr(elf_file: *Elf, writer: anytype) !void {
    const comp = elf_file.base.comp;
    const gpa = comp.gpa;

    try writer.writeByte(1); // version
    try writer.writeByte(EH_PE.pcrel | EH_PE.sdata4);
    try writer.writeByte(EH_PE.udata4);
    try writer.writeByte(EH_PE.datarel | EH_PE.sdata4);

    const eh_frame_shdr = elf_file.shdrs.items[elf_file.eh_frame_section_index.?];
    const eh_frame_hdr_shdr = elf_file.shdrs.items[elf_file.eh_frame_hdr_section_index.?];
    const num_fdes = @as(u32, @intCast(@divExact(eh_frame_hdr_shdr.sh_size - eh_frame_hdr_header_size, 8)));
    try writer.writeInt(
        u32,
        @as(u32, @bitCast(@as(
            i32,
            @truncate(@as(i64, @intCast(eh_frame_shdr.sh_addr)) - @as(i64, @intCast(eh_frame_hdr_shdr.sh_addr)) - 4),
        ))),
        .little,
    );
    try writer.writeInt(u32, num_fdes, .little);

    const Entry = struct {
        init_addr: u32,
        fde_addr: u32,

        pub fn lessThan(ctx: void, lhs: @This(), rhs: @This()) bool {
            _ = ctx;
            return lhs.init_addr < rhs.init_addr;
        }
    };

    var entries = std.ArrayList(Entry).init(gpa);
    defer entries.deinit();
    try entries.ensureTotalCapacityPrecise(num_fdes);

    for (elf_file.objects.items) |index| {
        const object = elf_file.file(index).?.object;
        for (object.fdes.items) |fde| {
            if (!fde.alive) continue;

            const relocs = fde.relocs(elf_file);
            assert(relocs.len > 0); // Should this be an error? Things are completely broken anyhow if this trips...
            const rel = relocs[0];
            const sym = elf_file.symbol(object.symbols.items[rel.r_sym()]);
            const P = @as(i64, @intCast(fde.address(elf_file)));
            const S = @as(i64, @intCast(sym.address(.{}, elf_file)));
            const A = rel.r_addend;
            entries.appendAssumeCapacity(.{
                .init_addr = @bitCast(@as(i32, @truncate(S + A - @as(i64, @intCast(eh_frame_hdr_shdr.sh_addr))))),
                .fde_addr = @as(
                    u32,
                    @bitCast(@as(i32, @truncate(P - @as(i64, @intCast(eh_frame_hdr_shdr.sh_addr))))),
                ),
            });
        }
    }

    std.mem.sort(Entry, entries.items, {}, Entry.lessThan);
    try writer.writeAll(std.mem.sliceAsBytes(entries.items));
}

const eh_frame_hdr_header_size: usize = 12;

const EH_PE = struct {
    pub const absptr = 0x00;
    pub const uleb128 = 0x01;
    pub const udata2 = 0x02;
    pub const udata4 = 0x03;
    pub const udata8 = 0x04;
    pub const sleb128 = 0x09;
    pub const sdata2 = 0x0A;
    pub const sdata4 = 0x0B;
    pub const sdata8 = 0x0C;
    pub const pcrel = 0x10;
    pub const textrel = 0x20;
    pub const datarel = 0x30;
    pub const funcrel = 0x40;
    pub const aligned = 0x50;
    pub const indirect = 0x80;
    pub const omit = 0xFF;
};

const x86_64 = struct {
    fn resolveReloc(rel: elf.Elf64_Rela, source: i64, target: i64, data: []u8) void {
        const r_type: elf.R_X86_64 = @enumFromInt(rel.r_type());
        switch (r_type) {
            .@"32" => std.mem.writeInt(i32, data[0..4], @as(i32, @truncate(target)), .little),
            .@"64" => std.mem.writeInt(i64, data[0..8], target, .little),
            .PC32 => std.mem.writeInt(i32, data[0..4], @as(i32, @intCast(target - source)), .little),
            .PC64 => std.mem.writeInt(i64, data[0..8], target - source, .little),
            else => unreachable,
        }
    }
};

const std = @import("std");
const assert = std.debug.assert;
const elf = std.elf;
const math = std.math;
const relocs_log = std.log.scoped(.link_relocs);
const relocation = @import("relocation.zig");

const Allocator = std.mem.Allocator;
const Atom = @import("Atom.zig");
const Elf = @import("../Elf.zig");
const Object = @import("Object.zig");
const Symbol = @import("Symbol.zig");
