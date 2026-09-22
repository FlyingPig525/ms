const std = @import("std");
const rl = @import("raylib");
const math = @import("math.zig");
const meta = @import("meta.zig");
const ui = @import("ui.zig");
const Inspector = @import("Inspector.zig");
const TwoDimensionalList = @import("two_dimensional_list.zig").TwoDimensionalList;
const IVec2 = math.IVec2;

const primary_color: i32 = 0x47bf98ff;
const secondary_color: i32 = 0x214e45ff;
const tertiary_color: i32 = 0x111d21ff;

fn Cell(comptime T: type) type {
    if (T == void) {
        return struct {
            hidden: bool = true,
            flagged: bool = false,
        };
    }
    return struct {
        hidden: bool = true,
        flagged: bool = false,
        value: T,
    };
}

fn defaultDrawTextEx(text: [:0]const u8, position: rl.Vector2, font_size: f32, tint: rl.Color) void {
    const font = rl.getFontDefault() catch @panic("Couldnt load default font");
    rl.drawTextEx(font, text, position, font_size, @floatFromInt(font.glyphPadding), tint);
}

const GridSpace = union(GridSpace.Type) {
    number: Cell(u8),
    mine: Cell(void),
    empty_cell: Cell(void),

    const Type = enum {
        number,
        mine,
        empty_cell,
    };
    pub fn hidden(this: GridSpace) bool {
        switch (this) {
            inline else => |v| {
                return v.hidden;
            },
        }
    }
    pub fn flagged(this: GridSpace) bool {
        switch (this) {
            inline else => |v| return v.flagged,
        }
    }

    pub fn reveal(this: *GridSpace, info: Board.AdjacentInformation) TwoDimensionalList(GridSpace).BoundsError!Type {
        if (!this.hidden()) return std.meta.activeTag(this.*);

        switch (this.*) {
            inline else => |*v| {
                v.hidden = false;
            },
        }
        if (this.* == .empty_cell) {
            try info.list.repeatAdjacent(info.x, info.y, reveal, .{ undefined, undefined });
        }
        return std.meta.activeTag(this.*);
    }

    pub fn fullFlagReveal(this: *GridSpace, info: Board.AdjacentInformation) !bool {
        if (this.hidden()) return false;
        if (this.* == .number) {
            const value = this.number.value;
            var flagged_cells: u8 = 0;
            var hidden_cells: u8 = 0;
            {
                comptime var x = -1;
                inline while (x <= 1) : (x += 1) {
                    comptime var y = -1;
                    inline while (y <= 1) : (y += 1) {
                        if (info.list.get(info.x + x, info.y + y)) |cell| {
                            if (cell.flagged()) flagged_cells += 1;
                            if (cell.hidden()) hidden_cells += 1;
                        }
                    }
                }
            }
            if (hidden_cells == flagged_cells) return false;
            if (flagged_cells >= value) {
                var x: i32 = -1;
                while (x <= 1) : (x += 1) {
                    var y: i32 = -1;
                    while (y <= 1) : (y += 1) {
                        if (info.list.getPtr(info.x + x, info.y + y)) |cell| blk: {
                            if (cell.flagged()) break :blk;
                            const t = try cell.reveal(.{ .x = info.x + x, .y = info.y + y, .list = info.list });
                            if (t == .mine) return true;
                        }
                    }
                }
                x = -1;
                while (x <= 1) : (x += 1) {
                    var y: i32 = -1;
                    while (y <= 1) : (y += 1) {
                        if (info.list.getPtr(info.x + x, info.y + y)) |cell| {
                            if (cell.* == .number) {
                                if (try cell.fullFlagReveal(.{ .x = info.x + x, .y = info.y + y, .list = info.list })) return true;
                            }
                        }
                    }
                }
            }
        }
        return false;
    }

    pub fn toggleFlag(this: *GridSpace) void {
        switch (this.*) {
            inline else => |*v| {
                if (!v.hidden) return;
                v.flagged = !v.flagged;
            },
        }
    }

    pub const DrawOptions = struct {
        x: i32,
        y: i32,
        width: f32 = 20,
        height: f32 = 20,
        hovering: bool = false,
    };
    pub fn draw(this: GridSpace, opt: DrawOptions) void {
        const x = @as(f32, @floatFromInt(opt.x)) * opt.width;
        const y = @as(f32, @floatFromInt(opt.y)) * opt.height;

        const rect = rl.Rectangle{
            .x = x,
            .y = y,
            .width = opt.width,
            .height = opt.height,
        };
        var color: rl.Color = .fromInt(tertiary_color);
        rl.drawRectangleRec(rect, .fromInt(tertiary_color));

        if (!this.hidden()) {
            switch (this) {
                .number => |num| {
                    var buf: [4]u8 = undefined;
                    const txt = std.fmt.bufPrintZ(&buf, "{d}", .{num.value}) catch @panic("ruh roh");
                    const font = rl.getFontDefault() catch @panic("no font");
                    const dim = rl.measureTextEx(font, txt, 10, @floatFromInt(font.glyphPadding));
                    defaultDrawTextEx(txt, .{ .x = x + (opt.width / 2) - (dim.x / 2), .y = y + (opt.height / 2) - (dim.y / 2) }, 10, .white);
                    color = (rl.Color.black).alpha(0);
                },
                .mine => {
                    //                    rl.drawRectangleRec(rect, .red);
                    color = .red;
                },
                .empty_cell => {},
            }
        } else {
            if (this.flagged()) {
                color = .dark_gray;
            } else {
                color = .fromInt(primary_color);
            }
            //            rl.drawRectangleRec(rect, .fromInt(primary_color));
        }
        rl.drawRectangleRec(rect, color);
        if (opt.hovering) {
            rl.drawRectangleRec(rect, rl.Color.white.alpha(0.4));
        }
        rl.drawRectangleLinesEx(rect, 0.5, .dark_gray);
    }
};

const Camera = struct {
    camera: rl.Camera2D,
    last_pos: rl.Vector2,
    target: rl.Vector2,
    duration: ?f64 = null,
    start_time: ?f64 = null,

    pub fn init(camera: rl.Camera2D) Camera {
        return .{
            .camera = camera,
            .last_pos = camera.target,
            .target = camera.target,
        };
    }

    pub fn animateShift(this: *Camera, x: f32, y: f32, duration: f64) void {
        this.animateMove(this.target.x + x, this.target.y + y, duration);
    }

    pub fn move(this: *Camera, x: f32, y: f32) void {
        this.last_pos = this.camera.target;
        this.target = .{ .x = x, .y = y };
        this.duration = null;
        this.start_time = null;
        this.camera.target = this.target;
    }

    pub fn animateMove(this: *Camera, x: f32, y: f32, duration: f64) void {
        this.last_pos = this.camera.target;
        this.target = .{ .x = x, .y = y };
        this.duration = duration;
        this.start_time = rl.getTime();
    }

    pub fn tick(this: *Camera) void {
        if (this.duration) |duration| {
            const target = this.target;
            const start_time = this.start_time.?;
            const last_pos = this.last_pos;
            if (!this.camera.target.equals(target)) blk: {
                const now = rl.getTime();
                if (start_time + duration <= now) {
                    this.camera.target = target;
                    break :blk;
                }
                const difference = target.subtract(last_pos);
                const multiplier = (now - start_time) / duration;
                const multiplied = difference.multiply(.{ .x = @floatCast(multiplier), .y = @floatCast(multiplier) });
                this.camera.target = last_pos.add(multiplied);
            } else {
                this.duration = null;
                this.start_time = null;
            }
        }
    }
};

const Board = struct {
    const chunk_size = 16;

    pub const Scene = std.AutoArrayHashMapUnmanaged(IVec2, Chunk);
    pub const Chunk = TwoDimensionalList(GridSpace);
    scene: Scene,
    chunk_bomb_count: u8,
    arena: std.heap.ArenaAllocator,
    cursor_pos: IVec2 = .{ .x = 0, .y = 0 },
    camera: *Camera,
    mode: Mode,
    end_thyself: bool = false,
    dead: bool = false,

    pub const Mode = enum {
        default,
        flag_only,
    };

    pub fn init(gpa: std.mem.Allocator, chunk_bomb_count: u8, camera: *Camera, mode: Mode) !Board {
        return .{
            .scene = .empty,
            .chunk_bomb_count = chunk_bomb_count,
            .arena = .init(gpa),
            .camera = camera,
            .mode = mode,
        };
    }

    pub fn deinit(this: Board) void {
        this.arena.deinit();
    }

    const min_camera_zoom = 1.8719;
    pub fn tick(this: *Board, dt: f32) !void {
        if (rl.isKeyPressed(.a) or rl.isKeyPressedRepeat(.a)) {
            this.cursor_pos.x -= 1;
            this.camera.animateShift(-20, 0, 0.2);
        }
        if (rl.isKeyPressed(.d) or rl.isKeyPressedRepeat(.d)) {
            this.cursor_pos.x += 1;
            this.camera.animateShift(20, 0, 0.2);
        }
        if (rl.isKeyPressed(.w) or rl.isKeyPressedRepeat(.w)) {
            this.cursor_pos.y -= 1;
            this.camera.animateShift(0, -20, 0.2);
        }
        if (rl.isKeyPressed(.s) or rl.isKeyPressedRepeat(.s)) {
            this.cursor_pos.y += 1;
            this.camera.animateShift(0, 20, 0.2);
        }
        if (rl.isKeyDown(.e)) {
            this.camera.camera.zoom = rl.math.clamp(this.camera.camera.zoom + (this.camera.camera.zoom * 3 * dt), min_camera_zoom, 100);
        }
        if (rl.isKeyDown(.q)) {
            this.camera.camera.zoom = rl.math.clamp(this.camera.camera.zoom - (this.camera.camera.zoom * 3 * dt), min_camera_zoom, 100);
        }
        if (rl.isKeyPressed(.r)) {
            this.camera.camera.zoom = min_camera_zoom;
        }

        if (rl.isKeyPressed(.space)) blk: {
            if (this.dead) {
                this.end_thyself = true;
                break :blk;
            }
            if (this.mode == .flag_only and !this.cursor_pos.eql(.{ .x = 1, .y = 1 })) break :blk;
            const ptr = this.getPtr(this.cursor_pos.x, this.cursor_pos.y) orelse {
                std.debug.print("null cell {d} {d}\n", .{ this.cursor_pos.x, this.cursor_pos.y });
                break :blk;
            };
            if (ptr.flagged()) break :blk;
            if (!ptr.hidden() and ptr.* == .number and this.mode != .flag_only) {
                if (try ptr.fullFlagReveal(.{ .x = this.cursor_pos.x, .y = this.cursor_pos.y, .list = this })) {
                    this.dead = true;
                }
            } else {
                const t = try ptr.reveal(.{ .x = this.cursor_pos.x, .y = this.cursor_pos.y, .list = this });
                if (t == .mine) {
                    this.dead = true;
                }
            }
        }

        if (rl.isKeyPressed(.f) or rl.isKeyPressed(.j)) blk: {
            if (this.dead) break :blk;
            const ptr = this.getPtr(this.cursor_pos.x, this.cursor_pos.y) orelse {
                std.debug.print("null cell {d} {d}\n", .{ this.cursor_pos.x, this.cursor_pos.y });
                break :blk;
            };
            ptr.toggleFlag();
            if (this.mode == .flag_only) {
                var x: i32 = -1;
                loop: while (x <= 1) : (x += 1) {
                    var y: i32 = -1;
                    while (y <= 1) : (y += 1) {
                        const cell = this.getPtr(this.cursor_pos.x + x, this.cursor_pos.y + y) orelse continue;
                        if (try cell.fullFlagReveal(.{ .x = this.cursor_pos.x + x, .y = this.cursor_pos.y + y, .list = this })) {
                            this.dead = true;
                            break :loop;
                        }
                    }
                }
            }
        }

        this.camera.tick();
    }

    pub fn setup(this: *Board, io: std.Io) !void {
        var prng = std.Random.DefaultPrng.init(@bitCast(std.Io.Timestamp.now(io, .real).toMilliseconds()));
        const random = prng.random();

        var chunk_x: i32 = -5;
        while (chunk_x < 5) : (chunk_x += 1) {
            var chunk_y: i32 = -5;
            while (chunk_y < 5) : (chunk_y += 1) {
                var chunk = try Chunk.initValued(this.arena.allocator(), chunk_size, chunk_size, .{ .empty_cell = .{} });
                defer this.scene.put(this.arena.allocator(), .{ .x = chunk_x, .y = chunk_y }, chunk) catch @panic("put failed");
                if (this.mode == .flag_only and chunk_x == 0 and chunk_y == 0) continue;
                for (0..this.chunk_bomb_count) |_| {
                    var found = false;
                    // blk just because i wanted to
                    blk: while (!found) {
                        const x = random.intRangeAtMost(usize, 0, chunk.list.len - 1);
                        if (x == 0) continue :blk;
                        if (chunk.list[x] != .empty_cell) {
                            continue :blk;
                        }
                        chunk.list[x] = .{
                            .mine = .{ .hidden = true },
                        };
                        found = true;
                    }
                }
            }
        }
        chunk_x = -5;
        while (chunk_x < 5) : (chunk_x += 1) {
            var chunk_y: i32 = -5;
            while (chunk_y < 5) : (chunk_y += 1) {
                const vec: IVec2 = .{ .x = chunk_x, .y = chunk_y };
                const chunk = this.scene.get(vec) orelse continue;
                var x: i32 = 0;
                while (x < chunk_size) : (x += 1) {
                    var y: i32 = 0;
                    while (y < chunk_size) : (y += 1) {
                        const cell = try chunk.get(x, y);
                        if (cell == .empty_cell) {
                            const abs = vec.multValue(chunk_size).add(.{ .x = x, .y = y });
                            const Int = math.OperableNumber(u8);
                            var cnt: Int = .{ .value = 0 };
                            this.repeatAdjacentNoInfoOnType(abs.x, abs.y, .mine, Int.add, .{ &cnt, 1 });
                            if (cnt.value > 0) {
                                chunk.silentSet(@intCast(x), @intCast(y), .{ .number = .{ .value = cnt.value, .hidden = true } });
                            }
                        }
                    }
                }
            }
        }
    }

    pub fn draw(this: *Board) !void {
        {
            rl.beginMode2D(this.camera.camera);
            defer rl.endMode2D();
            const tl_pos = rl.getScreenToWorld2D(.init(0, 0), this.camera.camera);
            const tl_vec = IVec2{ .x = @floor(tl_pos.x / 20), .y = @floor(tl_pos.y / 20) };
            const br_pos = rl.getScreenToWorld2D(.init(@floatFromInt(rl.getScreenWidth()), @floatFromInt(rl.getScreenHeight())), this.camera.camera);
            const br_vec = IVec2{ .x = @floor(br_pos.x / 20), .y = @floor(br_pos.y / 20) };
            var x = tl_vec.x;
            while (x <= br_vec.x) : (x += 1) {
                var y = tl_vec.y;
                while (y <= br_vec.y) : (y += 1) {
                    const cell = this.get(x, y) orelse continue;
                    cell.draw(.{ .x = x, .y = y, .width = 20, .height = 20, .hovering = this.cursor_pos.lEql(x, y) });
                }
            }
        }
        var buf: [20]u8 = undefined;
        const txt = try std.fmt.bufPrintZ(&buf, "Cursor: {d} {d}", .{ this.cursor_pos.x, this.cursor_pos.y });
        rl.drawText(txt, 0, 30, 24, .white);
        const chunk_pos = this.cursor_pos.floorDivValue(chunk_size);
        const chunk_text = try std.fmt.bufPrintZ(&buf, "Chunk: {d} {d}", .{ chunk_pos.x, chunk_pos.y });
        rl.drawText(chunk_text, 0, 50, 24, .white);
        if (this.dead) {
            const screen_width = rl.getScreenWidth();
            const str = "You are dead";
            const default = try rl.getFontDefault();
            const width = rl.measureTextEx(default, str, 64, @floatFromInt(default.glyphPadding));
            rl.drawText(str, @divFloor(screen_width, 2) - @as(i32, @trunc(width.x / 2)), 128, 64, .white);
            const str2 = "Press space to restart";
            const width2 = rl.measureText(str2, 64);
            rl.drawText(str2, @divFloor(screen_width, 2) - @divFloor(width2, 2), 128 + @as(i32, @trunc(width.y)) + 15, 64, .white);
        }
    }

    pub fn get(this: Board, x: i32, y: i32) ?GridSpace {
        const chunk_pos: IVec2 = .{ .x = @divFloor(x, chunk_size), .y = @divFloor(y, chunk_size) };
        const chunk = this.scene.get(chunk_pos) orelse return null;
        const relative_pos = (IVec2{ .x = x, .y = y }).sub(chunk_pos.multValue(chunk_size));
        return chunk.get(relative_pos.x, relative_pos.y) catch |err| blk: {
            std.log.err("Error encountered in Board.get: {any}", .{err});
            break :blk null;
        };
    }
    pub fn getPtr(this: Board, x: i32, y: i32) ?*GridSpace {
        const chunk_pos: IVec2 = .{ .x = @divFloor(x, chunk_size), .y = @divFloor(y, chunk_size) };
        const chunk = this.scene.get(chunk_pos) orelse return null;
        const relative_pos = (IVec2{ .x = x, .y = y }).sub(chunk_pos.multValue(chunk_size));
        return chunk.getPtr(relative_pos.x, relative_pos.y) catch |err| blk: {
            std.log.err("Error encountered in Board.get: {any}", .{err});
            break :blk null;
        };
    }
    const AdjacentInformation = struct { list: *Board, x: i32, y: i32 };
    /// Calls `func` for each adjacent cell, passing information about said adjacent cell to the function.
    ///
    /// This stupid method requires a very specific function layout.
    /// The signature of `func` must be `fn(T, AdjacentInformation, ...)`. All arguments after `AdjacentInformation` can be anything
    ///
    /// To call this method, set the first two values of `args` to undefined.
    /// Example: `list.repeatAdjacent(5, 3, worker, .{ undefined, undefined, 32, false })`
    pub fn repeatAdjacent(this: *@This(), cell_x: i32, cell_y: i32, comptime func: anytype, args: std.meta.ArgsTuple(@TypeOf(func))) meta.FnErrorUnionCompound(@TypeOf(func), void) {
        comptime var getFn: *const fn (@This(), i32, i32) ?@TypeOf(args[0]) = undefined;
        comptime if (@typeInfo(@TypeOf(args[0])) == .pointer) {
            getFn = getPtr;
        } else {
            getFn = get;
        };
        const errs = @typeInfo(@typeInfo(@TypeOf(func)).@"fn".return_type.?) == .error_union;
        var a: @TypeOf(args) = args;
        blk: {
            a[0] = getFn(this.*, cell_x - 1, cell_y - 1) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x - 1, .y = cell_y - 1 };
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
        blk: {
            a[0] = getFn(this.*, cell_x, cell_y - 1) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x, .y = cell_y - 1 };
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
        blk: {
            a[0] = getFn(this.*, cell_x + 1, cell_y - 1) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x + 1, .y = cell_y - 1 };
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
        blk: {
            a[0] = getFn(this.*, cell_x + 1, cell_y) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x + 1, .y = cell_y };
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
        blk: {
            a[0] = getFn(this.*, cell_x + 1, cell_y + 1) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x + 1, .y = cell_y + 1 };
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
        blk: {
            a[0] = getFn(this.*, cell_x, cell_y + 1) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x, .y = cell_y + 1 };
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
        blk: {
            a[0] = getFn(this.*, cell_x - 1, cell_y + 1) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x - 1, .y = cell_y + 1 };
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
        blk: {
            a[0] = getFn(this.*, cell_x - 1, cell_y) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x - 1, .y = cell_y };
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
    }
    /// The same as `repeatAdjacent`, except it provides no `AdjacentInfo` argument
    /// and places the `GridSpace` in the second parameter
    ///
    /// Also only calls the function when the `GridSpace` matches the provided tag
    pub fn repeatAdjacentNoInfoOnType(this: *Board, cell_x: i32, cell_y: i32, tag: GridSpace.Type, comptime func: anytype, args: std.meta.ArgsTuple(@TypeOf(func))) void {
        const getFn: *const fn (@This(), i32, i32) ?GridSpace = get;
        const a: @TypeOf(args) = args;
        const errs = @typeInfo(@typeInfo(@TypeOf(func)).@"fn".return_type.?) == .error_union;
        blk: {
            const c = getFn(this.*, cell_x - 1, cell_y - 1) orelse break :blk;
            if (c != tag) break :blk;
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
        blk: {
            const c = getFn(this.*, cell_x, cell_y - 1) orelse break :blk;
            if (c != tag) break :blk;
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
        blk: {
            const c = getFn(this.*, cell_x + 1, cell_y - 1) orelse break :blk;
            if (c != tag) break :blk;
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
        blk: {
            const c = getFn(this.*, cell_x + 1, cell_y) orelse break :blk;
            if (c != tag) break :blk;
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
        blk: {
            const c = getFn(this.*, cell_x + 1, cell_y + 1) orelse break :blk;
            if (c != tag) break :blk;
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
        blk: {
            const c = getFn(this.*, cell_x, cell_y + 1) orelse break :blk;
            if (c != tag) break :blk;
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
        blk: {
            const c = getFn(this.*, cell_x - 1, cell_y + 1) orelse break :blk;
            if (c != tag) break :blk;
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
        blk: {
            const c = getFn(this.*, cell_x - 1, cell_y) orelse break :blk;
            if (c != tag) break :blk;
            if (errs) _ = try @call(.auto, func, a) else _ = @call(.auto, func, a);
        }
    }
};

fn Menu(comptime Manager: type, comptime Enum: type, comptime func: *const fn (*Manager, Enum) void) type {
    if (@typeInfo(Enum) != .@"enum") @compileError("Enum must be an enum");
    const enum_info = @typeInfo(Enum).@"enum";
    const fields = enum_info.fields;
    if (fields.len == 0) @compileError("Enum must have at least one field");
    return struct {
        const This = @This();

        gpa: std.mem.Allocator,
        active: Enum,
        manager: *Manager,
        layout: *ui.LayoutNode,
        layout_node: *ui.Node,
        entries: [fields.len]*EntryNode,
        entry_nodes: [fields.len]*ui.Node,

        pub const EntryNode = struct {
            gpa: std.mem.Allocator,
            menu: *This,
            entry: Enum,
            text: *ui.TextNode,
            text_node: *ui.Node,
            rect: *ui.RectNode,
            rect_node: *ui.Node,
            selected: bool,

            const entry_vtable: ui.Node.VTable = .{
                .deinit = ui.Node.VTable.basicOpaqueDeinit(EntryNode),
                .calculate_size = calculateSize,
                .type_info = ui.Node.VTable.basicTypeInfo(EntryNode, &.{"selected"}),
                .cursor_pos = cursorPos,
            };

            pub fn init(gpa: std.mem.Allocator, menu: *This, entry: Enum, text: [:0]const u8) !*EntryNode {
                const node = try gpa.create(EntryNode);
                node.gpa = gpa;
                node.entry = entry;
                node.menu = menu;
                node.text = try ui.TextNode.initDefault(gpa, text, 24, .white);
                node.text_node = try node.text.toNode();
                try node.text_node.setId("entry-text");
                node.rect = try ui.RectNode.init(gpa, .blank);
                node.rect_node = try node.rect.toNode();
                try node.rect_node.setId("selector-square");
                node.rect_node.space.size.x = 3;
                node.selected = false;
                return node;
            }

            pub fn deinit(this: *EntryNode) void {
                this.gpa.destroy(this);
            }

            pub fn toNode(this: *EntryNode) !*ui.Node {
                const node = try ui.Node.init(this.gpa, this, .zero, &entry_vtable);
                try node.addChild(this.text_node);
                try node.addChild(this.rect_node);
                return node;
            }

            // this isnt how i would recommend doing this, but i cant think of a easier way right now
            fn calculateSize(node: *ui.Node) !rl.Vector2 {
                const this = node.mgr(EntryNode);
                try this.text_node.calculateSize();
                this.rect_node.space.size.y = this.text_node.space.size.y;
                return this.text_node.space.size.add(.init(12, 0));
            }

            fn cursorPos(node: *ui.Node, _: rl.Vector2, rel: ?rl.Vector2) !void {
                const this = node.mgr(EntryNode);
                if (rel) |_| {
                    this.menu.hover(this);
                }
            }

            pub fn deselect(this: *EntryNode) void {
                this.selected = false;
                this.text.tint = .white;
                this.text_node.space.offset.x = 0;
                this.rect.color = .blank;
            }

            pub fn select(this: *EntryNode) void {
                this.selected = true;
                this.text.tint = .light_gray;
                this.text_node.space.offset.x = 12;
                this.rect.color = .light_gray;
            }
        };

        pub fn init(gpa: std.mem.Allocator, manager: *Manager) !*This {
            const node = try gpa.create(This);
            node.gpa = gpa;
            node.active = @enumFromInt(fields[0].value);
            node.manager = manager;
            node.layout = try ui.LayoutNode.init(gpa, 12, .vertical, .start);
            node.layout_node = try node.layout.toNode();
            node.layout_node.space.offset.x = 12;
            inline for (0..fields.len) |i| {
                node.entries[i] = try .init(gpa, node, @enumFromInt(fields[i].value), fields[i].name);
                node.entry_nodes[i] = try node.entries[i].toNode();
                try node.entry_nodes[i].setId(fields[i].name);
                try node.layout_node.addChild(node.entry_nodes[i]);
            }
            node.entries[0].select();
            return node;
        }

        pub fn deinit(this: *This) void {
            this.gpa.destroy(this);
        }

        pub fn hover(this: *This, node: *EntryNode) void {
            this.active = node.entry;
            this.updateNodes();
        }

        pub fn updateNodes(this: *This) void {
            inline for (0..fields.len) |i| {
                this.entries[i].deselect();
                if (@intFromEnum(this.active) == fields[i].value) this.entries[i].select();
            }
        }

        fn onInput(node: *ui.Node, key: rl.KeyboardKey, _: bool) !ui.Propagation {
            const this = node.mgr(This);
            switch (key) {
                .j => {
                    inline for (fields, 0..) |field, i| {
                        if (field.value == @intFromEnum(this.active)) {
                            if (i == fields.len - 1) {
                                this.active = @enumFromInt(fields[0].value);
                            } else {
                                this.active = @enumFromInt(fields[i + 1].value);
                            }
                            break;
                        }
                    }
                    this.updateNodes();
                },
                .k => {
                    inline for (fields, 0..) |field, i| {
                        if (field.value == @intFromEnum(this.active)) {
                            if (i == 0) {
                                this.active = @enumFromInt(fields[fields.len - 1].value);
                            } else {
                                this.active = @enumFromInt(fields[i - 1].value);
                            }
                            break;
                        }
                    }

                    this.updateNodes();
                },
                .space => {
                    func(this.manager, this.active);
                },
                else => return .propagate,
            }
            return .dont_propagate;
        }

        fn onClick(node: *ui.Node, btn: rl.MouseButton, relative_pos: ?rl.Vector2) !ui.Propagation {
            const this = node.mgr(This);
            if (btn != .left) return .propagate;
            if (relative_pos == null) return .propagate;
            func(this.manager, this.active);
            return .consume;
        }

        const vtable: ui.Node.VTable = .{
            .deinit = ui.Node.VTable.basicOpaqueDeinit(This),
            .on_input = onInput,
            .type_info = ui.Node.VTable.basicTypeInfo(This, &.{}),
            .on_click = onClick,
        };
        pub fn toNode(this: *This) !*ui.Node {
            const node = try ui.Node.init(this.gpa, this, .zero, &vtable);
            try node.addChild(this.layout_node);
            return node;
        }
    };
}

pub const MenuManager = struct {
    const MainMenu = Menu(MenuManager, MainOptions, submitMainMenu);
    pub const MainOptions = enum {
        Resume,
        Restart,
        Mode,
        Exit,
    };
    const ModeMenu = Menu(MenuManager, ModeOptions, submitModeMenu);
    pub const ModeOptions = enum {
        Default,
        @"Flags Only",
        Back,
    };
    fn NodePair(comptime Manager: type) type {
        if (!@hasDecl(Manager, "toNode")) @compileError("Manager must have a toNode method");
        return struct {
            manager: *Manager,
            node: *ui.Node,

            pub fn init(manager: *Manager) !@This() {
                return .{
                    .manager = manager,
                    .node = try manager.toNode(),
                };
            }
        };
    }

    gpa: std.mem.Allocator,
    layout: *ui.LayoutNode,
    layout_node: *ui.Node,
    main_menu: ?NodePair(MainMenu),
    mode_menu: ?NodePair(ModeMenu),
    exit_ptr: *bool,
    restart_ptr: *bool,
    target_mode_ptr: *Board.Mode,

    pub fn init(gpa: std.mem.Allocator, exit_ptr: *bool, restart_ptr: *bool, target_mode_ptr: *Board.Mode) !*MenuManager {
        const node = try gpa.create(MenuManager);
        node.gpa = gpa;
        node.layout = try ui.LayoutNode.init(gpa, 12, .horizontal, .start);
        node.layout_node = try node.layout.toNode();
        node.main_menu = null;
        node.mode_menu = null;
        node.exit_ptr = exit_ptr;
        node.restart_ptr = restart_ptr;
        node.target_mode_ptr = target_mode_ptr;
        return node;
    }

    pub fn deinit(this: *MenuManager) void {
        this.gpa.destroy(this);
    }

    pub fn open(this: *MenuManager) !void {
        if (this.main_menu != null) return;
        this.main_menu = try .init(try MainMenu.init(this.gpa, this));
        try this.layout_node.addChild(this.main_menu.?.node);
        try this.layout_node.recalculateNodeGraphSize();
    }

    pub fn openMode(this: *MenuManager) !void {
        if (this.mode_menu != null) return;
        if (this.main_menu == null) @panic("main menu null when mode menu is opening");
        this.mode_menu = try .init(try ModeMenu.init(this.gpa, this));
        try this.layout_node.addChild(this.mode_menu.?.node);
        try this.layout_node.recalculateNodeGraphSize();
        this.main_menu.?.node.frozen = true;
    }

    pub fn close(this: *MenuManager) !void {
        if (this.main_menu) |m| {
            if (m.node.parent) |p| {
                try m.node.setId("llllldwijaiwa");
                if (!p.removeChildId("llllldwijaiwa")) @panic("what");
            } else {
                m.node.deinit();
            }
            this.main_menu = null;
        }
        if (this.mode_menu) |m| {
            if (m.node.parent) |p| {
                try m.node.setId("llllldwijaiwa");
                if (!p.removeChildId("llllldwijaiwa")) @panic("what");
            } else {
                m.node.deinit();
            }
            this.mode_menu = null;
        }
        try this.layout_node.recalculateNodeGraphSize();
    }

    pub fn closeMode(this: *MenuManager) !void {
        if (this.mode_menu) |m| {
            if (m.node.parent) |p| {
                try m.node.setId("llllldwijaiwa");
                if (!p.removeChildId("llllldwijaiwa")) @panic("what");
            } else {
                m.node.deinit();
            }
            this.mode_menu = null;
        }
        if (this.main_menu) |m| m.node.frozen = false;
        try this.layout_node.recalculateNodeGraphSize();
    }

    fn submitMainMenu(this: *MenuManager, active: MainOptions) void {
        switch (active) {
            .Resume => this.close() catch |err| std.debug.panicExtra(null, "menu close failure {any}", .{err}),
            .Restart => {
                this.restart_ptr.* = true;
                this.close() catch |err| std.debug.panicExtra(null, "menu close failute {any}", .{err});
            },
            .Mode => this.openMode() catch |err| std.debug.panicExtra(null, "mode open failure {any}", .{err}),
            .Exit => {
                this.exit_ptr.* = true;
                this.close() catch |err| std.debug.panicExtra(null, "menu close failure {any}", .{err});
            },
        }
    }
    fn submitModeMenu(this: *MenuManager, active: ModeOptions) void {
        switch (active) {
            .Default => {
                this.target_mode_ptr.* = .default;
                this.restart_ptr.* = true;
                this.close() catch |err| std.debug.panicExtra(null, "menu close failure {any}", .{err});
            },
            .@"Flags Only" => {
                this.target_mode_ptr.* = .flag_only;
                this.restart_ptr.* = true;
                this.close() catch |err| std.debug.panicExtra(null, "menu close failure {any}", .{err});
            },
            .Back => {
                this.closeMode() catch |err| std.debug.panicExtra(null, "mode close failure {any}", .{err});
            },
        }
    }

    const vtable: ui.Node.VTable = .{
        .deinit = ui.Node.VTable.basicOpaqueDeinit(MenuManager),
        .type_info = ui.Node.VTable.basicTypeInfo(MenuManager, &.{}),
    };
    pub fn toNode(this: *MenuManager) !*ui.Node {
        const node = try ui.Node.init(this.gpa, this, .zero, &vtable);
        try node.addChild(this.layout_node);
        return node;
    }
};

fn iterateKeysPressed() ?rl.KeyboardKey {
    const key = rl.getKeyPressed();
    if (key == .null) return null;
    return key;
}

pub fn main(init: std.process.Init) !void {
    const screen_width = 1080;
    const screen_height = 720;

    rl.initWindow(screen_width, screen_height, "Minesweeeeeper");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var camera: Camera = .init(.{
        .target = .{ .x = 10, .y = 10 },
        .offset = .{ .x = screen_width / 2, .y = screen_height / 2 },
        .rotation = 0,
        .zoom = 1.8729,
    });
    rl.setExitKey(.null);
    var should_exit = false;
    var should_restart = false;

    var inspector = try Inspector.init(init.gpa, screen_width, screen_height);
    defer inspector.deinit();

    // TODO: for some reason when these are different values, things dont scale correctly. i dont know why yet
    var root = ui.RootNode{
        .screen_size = .init(screen_width, screen_height),
        .true_size = .init(screen_width, screen_height),
    };
    const root_node = try root.toNode(init.gpa);
    defer root_node.deinit();
    var target_mode: Board.Mode = .default;
    const menu = try MenuManager.init(init.gpa, &should_exit, &should_restart, &target_mode);
    const menu_node = try menu.toNode();
    menu_node.space.offset.y = 30;
    try root_node.addChild(menu_node);

    try inspector.setRoot(root_node);

    var keys_pressed: std.ArrayList(rl.KeyboardKey) = .empty;
    defer keys_pressed.deinit(init.gpa);

    //    var menu_data = ui.Menu.init(&.{
    //        try .init(init.gpa, "Resume", resumeFromMenu),
    //        try .init(init.gpa, "Exit", exitFromMenu),
    //    });
    //    defer menu_data.deinit(init.gpa);
    while (!(should_exit or rl.windowShouldClose())) {
        should_restart = false;
        camera.move(10, 10);
        var board = try Board.init(init.gpa, 60, &camera, target_mode);
        defer board.deinit();
        try board.setup(init.io);
        var last_cursor = inspector.translate(rl.getMousePosition().divide(root.true_size).multiply(root.screen_size));
        while (!(should_exit or board.end_thyself or should_restart or rl.windowShouldClose())) {
            const dt = rl.getFrameTime();
            if (rl.isKeyDown(.left_shift) and rl.isKeyPressed(.escape)) {
                should_exit = true;
                break;
            }
            if (rl.isKeyPressed(.escape)) {
                try menu.open();
            }
            if (rl.isKeyPressed(.p)) {
                inspector.is_open = !inspector.is_open;
            }
            const cursor = inspector.translate(rl.getMousePosition().divide(root.true_size).multiply(root.screen_size));
            defer last_cursor = cursor;
            if (!cursor.equals(last_cursor)) {
                try root_node.cursorPos(cursor, cursor);
            }
            try root_node.tick(dt);
            if (menu.main_menu == null) {
                try board.tick(dt);
            } else {
                while (iterateKeysPressed()) |key| {
                    try keys_pressed.append(init.gpa, key);
                    if (menu.main_menu != null) {
                        _ = try root_node.onInput(key, false);
                    }
                }
                for (keys_pressed.items, 0..) |key, i| {
                    if (rl.isKeyUp(key)) {
                        _ = keys_pressed.swapRemove(i);
                        continue;
                    }
                    if (rl.isKeyPressedRepeat(key)) {
                        if (menu.main_menu != null) {
                            _ = try root_node.onInput(key, true);
                        }
                    }
                }
                if (rl.isMouseButtonPressed(.left)) {
                    _ = try root_node.onClick(.left, cursor);
                }
                try root_node.tick(rl.getFrameTime());
            }
            if ((should_exit or board.end_thyself or should_restart or rl.windowShouldClose())) {
                continue;
            }
            rl.beginDrawing();
            defer rl.endDrawing();
            {
                inspector.beginDraw();
                defer inspector.endDraw();
                rl.clearBackground(.black);
                if (menu.main_menu == null) {
                    try board.draw();
                } else {
                    try root_node.draw();
                }
                rl.drawFPS(0, 0);
            }
            try inspector.draw();
        }
    }
}
