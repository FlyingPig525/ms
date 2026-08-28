const std = @import("std");
const rl = @import("raylib");
const math = @import("math.zig");
const IVec2 = math.IVec2;

const primary_color: i32 = 0x47bf98ff;
const secondary_color: i32 = 0x214e45ff;
const tertiary_color: i32 = 0x111d21ff;

fn StackTwoDimensionalList(comptime T: type, comptime width: i32, comptime height: i32) type {
    return struct {
        const ListT = TwoDimensionalList(T);
        list: ListT,
        buf: [@intCast(width * height)]T,

        pub fn init() @This() {
            var list = @This(){
                .list = undefined,
                .buf = undefined,
            };
            list = ListT.initBuffered(&list.buf, width, height) catch unreachable;
            return list;
        }
        pub fn initValued(value: T) @This() {
            var list = init();
            _ = &list;
            @memset(list.list, value);
            return list;
        }

        pub fn get(this: @This(), x: i32, y: i32) ListT.BoundsError!T {
            return this.list.get(x, y);
        }

        pub fn getPtr(this: @This(), x: i32, y: i32) ListT.BoundsError!*T {
            return this.list.getPtr(x, y);
        }

        pub fn set(this: @This(), x: i32, y: i32, item: T) ListT.BoundsError!void {
            return this.list.set(x, y, item);
        }

        pub fn silentSet(this: @This(), x: i32, y: i32, item: T) void {
            return this.list.silentSet(x, y, item);
        }

        pub fn repeatAdjacent(this: *@This(), cell_x: i32, cell_y: i32, comptime func: anytype, args: std.meta.ArgsTuple(@TypeOf(func))) !void {
            return this.list.repeatAdjacent(cell_x, cell_y, func, args);
        }
    };
}

fn TwoDimensionalList(comptime T: type) type {
    return struct {
        list: []T,
        width: i32,
        height: i32,
        buffered: bool,

        pub fn init(gpa: std.mem.Allocator, width: i32, height: i32) !@This() {
            return .{
                .list = try gpa.alloc(T, @intCast(width * height)),
                .width = width,
                .height = height,
                .buffered = false,
            };
        }
        pub fn initValued(gpa: std.mem.Allocator, width: i32, height: i32, value: T) !@This() {
            var list = try init(gpa, width, height);
            _ = &list;
            @memset(list.list, value);
            return list;
        }

        pub fn deinit(this: @This(), gpa: std.mem.Allocator) void {
            if (this.buffered) return;
            gpa.free(this.list);
        }

        pub const BufferedInitError = error{InsufficientCapacity};
        /// Creates a TwoDimensionalList from an existing buffer. If the size of the buffer cannot fit the list,
        /// `BufferedInitError.InsufficientCapacity` is returned.
        ///
        /// The underlying slice in the constructed list is a slice of the exact length required.
        pub fn initBuffered(buf: []T, width: i32, height: i32) BufferedInitError!@This() {
            if (@as(i32, @intCast(buf.len)) < width * height) return BufferedInitError.InsufficientCapacity;
            return .{
                .list = buf[0..@intCast(width * height)],
                .width = width,
                .height = height,
                .buffered = true,
            };
        }

        pub const BoundsError = error{ XOutOfBounds, YOutOfBounds };

        pub fn get(this: @This(), x: i32, y: i32) BoundsError!T {
            return (try this.getPtr(x, y)).*;
        }

        pub fn getPtr(this: @This(), x: i32, y: i32) BoundsError!*T {
            if (x < 0) return BoundsError.XOutOfBounds;
            if (y < 0) return BoundsError.YOutOfBounds;
            if (x >= this.width) return BoundsError.XOutOfBounds;
            if (y >= this.height) return BoundsError.YOutOfBounds;
            return &this.list[@intCast((y * this.width) + x)];
        }

        pub fn set(this: @This(), x: i32, y: i32, item: T) BoundsError!void {
            if (x >= this.width) return BoundsError.XOutOfBounds;
            if (y >= this.height) return BoundsError.YOutOfBounds;
            this.list[@intCast((y * this.width) + x)] = item;
        }

        pub fn silentSet(this: @This(), x: i32, y: i32, item: T) void {
            this.list[@intCast((y * this.width) + x)] = item;
        }

        const List = @This();
        const AdjacentInformation = struct {
            list: *List,
            x: i32,
            y: i32,
        };
        /// Calls `func` for each adjacent cell, passing information about said adjacent cell to the function.
        ///
        /// This stupid method requires a very specific function layout.
        /// The signature of `func` must be `fn(T, AdjacentInformation, ...)`. All arguments after `AdjacentInformation` can be anything
        ///
        /// To call this method, set the first two values of `args` to undefined.
        /// Example: `list.repeatAdjacent(5, 3, worker, .{ undefined, undefined, 32, false })`
        pub fn repeatAdjacent(this: *@This(), cell_x: i32, cell_y: i32, comptime func: anytype, args: std.meta.ArgsTuple(@TypeOf(func))) !void {
            comptime var getFn: *const fn (@This(), i32, i32) anyerror!@TypeOf(args[0]) = undefined;
            comptime if (@typeInfo(@TypeOf(args[0])) == .pointer) {
                getFn = getPtr;
            } else {
                getFn = get;
            };
            var a: @TypeOf(args) = args;
            blk: {
                a[0] = getFn(this.*, cell_x - 1, cell_y - 1) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x - 1, .y = cell_y - 1 };
                try @call(.auto, func, a);
            }
            blk: {
                a[0] = getFn(this.*, cell_x, cell_y - 1) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x, .y = cell_y - 1 };
                try @call(.auto, func, a);
            }
            blk: {
                a[0] = getFn(this.*, cell_x + 1, cell_y - 1) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x + 1, .y = cell_y - 1 };
                try @call(.auto, func, a);
            }
            blk: {
                a[0] = getFn(this.*, cell_x + 1, cell_y) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x + 1, .y = cell_y };
                try @call(.auto, func, a);
            }
            blk: {
                a[0] = getFn(this.*, cell_x + 1, cell_y + 1) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x + 1, .y = cell_y + 1 };
                try @call(.auto, func, a);
            }
            blk: {
                a[0] = getFn(this.*, cell_x, cell_y + 1) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x, .y = cell_y + 1 };
                try @call(.auto, func, a);
            }
            blk: {
                a[0] = getFn(this.*, cell_x - 1, cell_y + 1) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x - 1, .y = cell_y + 1 };
                try @call(.auto, func, a);
            }
            blk: {
                a[0] = getFn(this.*, cell_x - 1, cell_y) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x - 1, .y = cell_y };
                try @call(.auto, func, a);
            }
        }
    };
}

fn Hidden(comptime T: type) type {
    if (T == void) {
        return struct {
            hidden: bool,
            pub const default: @This() = .{ .hidden = true };
        };
    }
    return struct {
        hidden: bool,
        value: T,
    };
}

fn defaultDrawTextEx(text: [:0]const u8, position: rl.Vector2, font_size: f32, tint: rl.Color) void {
    const font = rl.getFontDefault() catch @panic("Couldnt load default font");
    rl.drawTextEx(font, text, position, font_size, @floatFromInt(font.glyphPadding), tint);
}

const GridSpace = union(enum) {
    number: Hidden(u8),
    mine: Hidden(void),
    empty_cell: Hidden(void),

    pub fn hidden(this: GridSpace) bool {
        switch (this) {
            inline else => |v| {
                return v.hidden;
            },
        }
    }

    pub fn reveal(this: *GridSpace, info: Board.AdjacentInformation, scene: *Board.Scene) TwoDimensionalList(GridSpace).BoundsError!void {
        if (!this.hidden()) return;

        switch (this.*) {
            inline else => |*v| {
                v.hidden = false;
            },
        }
        if (this.* == .empty_cell) {
            try info.list.repeatAdjacent(info.x, info.y, reveal, .{ undefined, undefined, scene });
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
            color = .fromInt(primary_color);
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

    pub fn init(gpa: std.mem.Allocator, chunk_bomb_count: u8, camera: *Camera) !Board {
        return .{
            .scene = .empty,
            .chunk_bomb_count = chunk_bomb_count,
            .arena = .init(gpa),
            .camera = camera,
        };
    }

    pub fn deinit(this: Board) void {
        this.arena.deinit();
    }

    pub fn tick(this: *Board) !void {
        //        const dt = rl.getFrameTime();
        //        const mouse_pos_screen = rl.getMousePosition();

        //        const mouse_pos = rl.getScreenToWorld2D(mouse_pos_screen, this.camera.camera);

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
            this.camera.camera.zoom *= 1.1;
        }
        if (rl.isKeyDown(.q)) {
            this.camera.camera.zoom *= 0.9;
        }
        if (rl.isKeyPressed(.r)) {
            this.camera.camera.zoom = 1;
        }

        if (rl.isKeyPressed(.space)) blk: {
            const ptr = this.getPtr(this.cursor_pos.x, this.cursor_pos.y) orelse {
                std.debug.print("null cell {d} {d}\n", .{ this.cursor_pos.x, this.cursor_pos.y });
                break :blk;
            };
            try ptr.reveal(.{ .x = this.cursor_pos.x, .y = this.cursor_pos.y, .list = this }, &this.scene);
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
                std.debug.print("genning {d} {d}\n", .{ chunk_x, chunk_y });
                var chunk = try Chunk.initValued(this.arena.allocator(), chunk_size, chunk_size, .{ .empty_cell = .default });
                for (0..this.chunk_bomb_count) |_| {
                    var found = false;
                    // blk just because i wanted to
                    blk: while (!found) {
                        const x = random.intRangeAtMost(usize, 0, chunk.list.len - 1);
                        if (chunk.list[x] != .empty_cell) {
                            continue :blk;
                        }
                        chunk.list[x] = .{
                            .mine = .{ .hidden = true },
                        };
                        found = true;
                    }
                }
                this.scene.put(this.arena.allocator(), .{ .x = chunk_x, .y = chunk_y }, chunk) catch @panic("put failed");
            }
        }
        chunk_x = -5;
        while (chunk_x < 5) : (chunk_x += 1) {
            var chunk_y: i32 = -5;
            while (chunk_y < 5) : (chunk_y += 1) {
                const vec: IVec2 = .{ .x = chunk_x, .y = chunk_y };
                const chunk = this.scene.get(vec) orelse continue;
                const l_chunk: ?Chunk = this.scene.get(vec.lAdd(-1, 0));
                const r_chunk: ?Chunk = this.scene.get(vec.lAdd(1, 0));
                const t_chunk: ?Chunk = this.scene.get(vec.lAdd(0, -1));
                const b_chunk: ?Chunk = this.scene.get(vec.lAdd(0, 1));
                const tl_chunk: ?Chunk = this.scene.get(vec.lAdd(-1, -1));
                const tr_chunk: ?Chunk = this.scene.get(vec.lAdd(1, -1));
                const bl_chunk: ?Chunk = this.scene.get(vec.lAdd(-1, 1));
                const br_chunk: ?Chunk = this.scene.get(vec.lAdd(1, 1));
                var x: i32 = 0;
                while (x < chunk_size) : (x += 1) {
                    var y: i32 = 0;
                    while (y < chunk_size) : (y += 1) {
                        const cell = try chunk.get(x, y);
                        if (cell == .empty_cell) {
                            var cnt: u8 = 0;
                            var adj_x: i8 = -1;
                            while (adj_x < 2) : (adj_x += 1) {
                                var adj_y: i8 = -1;
                                wh: while (adj_y < 2) : (adj_y += 1) {
                                    const adj = blk: {
                                        const xP = x + adj_x;
                                        const yP = y + adj_y;
                                        if (xP < 0 and yP < 0) if (tl_chunk) |tl| {
                                            break :blk try tl.get(chunk_size + xP, chunk_size + yP);
                                        } else continue :wh;
                                        if (xP >= chunk_size and yP >= chunk_size) if (tr_chunk) |tr| {
                                            break :blk try tr.get(xP - chunk_size, yP - chunk_size);
                                        } else continue :wh;
                                        if (xP < 0 and yP >= chunk_size) if (bl_chunk) |bl| {
                                            break :blk try bl.get(chunk_size + xP, yP - chunk_size);
                                        } else continue :wh;
                                        if (xP >= chunk_size and yP < 0) if (br_chunk) |br| {
                                            break :blk try br.get(xP - chunk_size, chunk_size + yP);
                                        } else continue :wh;
                                        if (xP < 0) if (l_chunk) |l| {
                                            break :blk try l.get(chunk_size + xP, yP);
                                        } else continue :wh;
                                        if (yP < 0) if (t_chunk) |t| {
                                            break :blk try t.get(xP, chunk_size + yP);
                                        } else continue :wh;
                                        if (xP >= chunk_size) if (r_chunk) |r| {
                                            break :blk try r.get(xP - chunk_size, yP);
                                        } else continue :wh;
                                        if (yP >= chunk_size) if (b_chunk) |b| {
                                            break :blk try b.get(xP, yP - chunk_size);
                                        } else continue :wh;
                                        break :blk chunk.get(xP, yP) catch continue :wh;
                                    };
                                    if (adj == .mine) cnt += 1;
                                }
                            }
                            if (cnt > 0) {
                                chunk.silentSet(@intCast(x), @intCast(y), .{ .number = .{ .value = cnt, .hidden = true } });
                            }
                        }
                    }
                }
            }
        }
    }

    pub fn draw(this: Board) !void {
        {
            rl.beginMode2D(this.camera.camera);
            defer rl.endMode2D();

            const camera_chunk = this.camera.target.divide(.{ .x = chunk_size * 20, .y = chunk_size * 20 });
            const center_x: i32 = @intFromFloat(camera_chunk.x);
            const center_y: i32 = @intFromFloat(camera_chunk.y);
            var chunk_x = center_x - 2;
            while (chunk_x < center_x + 2) : (chunk_x += 1) {
                var chunk_y = center_y - 2;
                while (chunk_y < center_y + 2) : (chunk_y += 1) {
                    const chunk_n = this.scene.get(.{ .x = chunk_x, .y = chunk_y });
                    if (chunk_n) |chunk| {
                        for (0..chunk_size) |x| {
                            for (0..chunk_size) |y| {
                                const cell = chunk.get(@intCast(x), @intCast(y)) catch unreachable;
                                const diffed_cursor = this.cursor_pos.sub(.{ .x = chunk_x * chunk_size, .y = chunk_y * chunk_size });
                                cell.draw(.{ .x = @as(i32, @intCast(x)) + (chunk_x * chunk_size), .y = @as(i32, @intCast(y)) + (chunk_y * chunk_size), .width = 20, .height = 20, .hovering = diffed_cursor.lEql(@intCast(x), @intCast(y)) });
                            }
                        }
                    }
                }
            }
        }
        var buf: [20]u8 = undefined;
        const txt = try std.fmt.bufPrintZ(&buf, "Cursor: {d} {d}", .{ this.cursor_pos.x, this.cursor_pos.y });
        rl.drawText(txt, 0, 30, 24, .white);
        const chunk_pos = this.cursor_pos.floorDivValue(chunk_size);
        const chunk_text = try std.fmt.bufPrintZ(&buf, "Chunk: {d} {d}", .{ chunk_pos.x, chunk_pos.y });
        rl.drawText(chunk_text, 0, 50, 24, .white);
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
    pub fn repeatAdjacent(this: *@This(), cell_x: i32, cell_y: i32, comptime func: anytype, args: std.meta.ArgsTuple(@TypeOf(func))) !void {
        comptime var getFn: *const fn (@This(), i32, i32) ?@TypeOf(args[0]) = undefined;
        comptime if (@typeInfo(@TypeOf(args[0])) == .pointer) {
            getFn = getPtr;
        } else {
            getFn = get;
        };
        var a: @TypeOf(args) = args;
        blk: {
            a[0] = getFn(this.*, cell_x - 1, cell_y - 1) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x - 1, .y = cell_y - 1 };
            try @call(.auto, func, a);
        }
        blk: {
            a[0] = getFn(this.*, cell_x, cell_y - 1) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x, .y = cell_y - 1 };
            try @call(.auto, func, a);
        }
        blk: {
            a[0] = getFn(this.*, cell_x + 1, cell_y - 1) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x + 1, .y = cell_y - 1 };
            try @call(.auto, func, a);
        }
        blk: {
            a[0] = getFn(this.*, cell_x + 1, cell_y) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x + 1, .y = cell_y };
            try @call(.auto, func, a);
        }
        blk: {
            a[0] = getFn(this.*, cell_x + 1, cell_y + 1) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x + 1, .y = cell_y + 1 };
            try @call(.auto, func, a);
        }
        blk: {
            a[0] = getFn(this.*, cell_x, cell_y + 1) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x, .y = cell_y + 1 };
            try @call(.auto, func, a);
        }
        blk: {
            a[0] = getFn(this.*, cell_x - 1, cell_y + 1) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x - 1, .y = cell_y + 1 };
            try @call(.auto, func, a);
        }
        blk: {
            a[0] = getFn(this.*, cell_x - 1, cell_y) orelse break :blk;
            a[1] = AdjacentInformation{ .list = this, .x = cell_x - 1, .y = cell_y };
            try @call(.auto, func, a);
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const screenWidth = 1080;
    const screenHeight = 720;

    rl.initWindow(screenWidth, screenHeight, "Minesweeeeeper");
    defer rl.closeWindow();

    var camera: Camera = .init(.{
        .target = .{ .x = 10, .y = 10 },
        .offset = .{ .x = screenWidth / 2, .y = screenHeight / 2 },
        .rotation = 0,
        .zoom = 1,
    });
    var board = try Board.init(init.gpa, 50, &camera);
    defer board.deinit();
    try board.setup(init.io);

    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        try board.tick();
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);
        try board.draw();
        rl.drawFPS(0, 0);
    }
}
