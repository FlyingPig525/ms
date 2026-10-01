const std = @import("std");
const rl = @import("raylib");
const math = @import("math.zig");
const meta = @import("meta.zig");
const ui = @import("ui.zig");
const fast = @import("fastnoise.zig");
const Inspector = @import("Inspector.zig");
const TwoDimensionalList = @import("two_dimensional_list.zig").TwoDimensionalList;
const IVec2 = math.IVec2;
const ArrayIterator = @import("array_iterator.zig").ArrayIterator;
const easing = @import("easing.zig");

const primary_color: i32 = 0x47bf98ff;
const secondary_color: i32 = 0x214e45ff;
const tertiary_color: i32 = 0x111d21ff;

fn Cell(comptime T: type) type {
    if (T == void) {
        return struct {
            hidden: bool = true,
            flags: u8 = 0,
            biome: Biome,
        };
    }
    return struct {
        hidden: bool = true,
        flags: u8 = 0,
        biome: Biome,
        value: T,
    };
}

fn defaultDrawTextEx(text: [:0]const u8, position: rl.Vector2, font_size: f32, tint: rl.Color) void {
    const font = rl.getFontDefault() catch unreachable;
    rl.drawTextEx(font, text, position, font_size, @floatFromInt(font.glyphPadding), tint);
}

const GridSpace = union(GridSpace.Type) {
    number: Cell(u8),
    mine: Cell(u8),
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
            inline else => |v| return v.flags > 0,
        }
    }
    pub fn flags(this: GridSpace) u8 {
        switch (this) {
            inline else => |v| return v.flags,
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
            var n = this.neighbors(.{ .x = info.x, .y = info.y });
            while (n.next()) |vec| {
                const abs = vec.lAdd(info.x, info.y);
                if (info.list.getPtr(abs.x, abs.y)) |cell| {
                    _ = try cell.reveal(.{ .x = abs.x, .y = abs.y, .list = info.list });
                }
            }
        }
        return std.meta.activeTag(this.*);
    }

    pub fn colors(this: GridSpace, pos: IVec2) CellColors {
        return this.biome().colors(pos);
    }

    pub const Neighbors = ArrayIterator(IVec2, 5 * 5);
    pub fn neighbors(this: GridSpace, pos: IVec2) Neighbors {
        return this.biome().neighbors(pos);
    }

    pub fn rateMod(this: GridSpace) f32 {
        return this.biome().rateMod();
    }

    pub fn biome(this: GridSpace) Biome {
        switch (this) {
            inline else => |a| {
                return a.biome;
            },
        }
    }

    pub fn fullFlagReveal(this: *GridSpace, info: Board.AdjacentInformation, caller: IVec2) !bool {
        if (this.hidden()) return false;
        if (this.* == .number) {
            const value = this.number.value;
            var flagged_cells: u8 = 0;
            var flag_cnt: u8 = 0;
            var hidden_cells: u8 = 0;
            var n = this.neighbors(.{ .x = info.x, .y = info.y });
            while (n.next()) |vec| {
                const abs = vec.lAdd(info.x, info.y);
                if (info.list.get(abs.x, abs.y)) |cell| {
                    if (cell.flagged()) {
                        flagged_cells += 1;
                        flag_cnt += cell.flags();
                    }
                    if (cell.hidden()) hidden_cells += 1;
                }
            }
            if (hidden_cells == flagged_cells) return false;
            if (flag_cnt >= value) {
                n.reset();
                while (n.next()) |vec| {
                    if (vec.eql(.zero)) continue;
                    const abs = vec.lAdd(info.x, info.y);
                    if (abs.eql(caller)) continue;
                    if (info.list.getPtr(abs.x, abs.y)) |cell| blk: {
                        if (cell.flagged()) break :blk;
                        const t = try cell.reveal(.{ .x = abs.x, .y = abs.y, .list = info.list });
                        if (t == .mine) return true;
                    }
                }
                n.reset();
                while (n.next()) |vec| {
                    if (vec.eql(.zero)) continue;
                    const abs = vec.lAdd(info.x, info.y);
                    if (info.list.getPtr(abs.x, abs.y)) |cell| {
                        if (cell.* == .number) {
                            if (try cell.fullFlagReveal(.{ .x = abs.x, .y = abs.y, .list = info.list }, .{ .x = info.x, .y = info.y })) return true;
                        }
                    }
                }
            }
        }
        return false;
    }

    pub fn flag(this: *GridSpace) void {
        switch (this.*) {
            inline else => |*v| {
                if (!v.hidden) return;
                if (v.flags + 1 > this.biome().maxBombs()) v.flags = 0 else v.flags += 1;
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
        const c = this.colors(.{ .x = opt.x, .y = opt.y });
        var color: rl.Color = c.background;
        rl.drawRectangleRec(rect, c.background);

        if (!this.hidden()) {
            switch (this) {
                .number => |num| {
                    var buf: [4]u8 = undefined;
                    const txt = std.fmt.bufPrintZ(&buf, "{d}", .{num.value}) catch unreachable;
                    const font = rl.getFontDefault() catch unreachable;
                    const dim = rl.measureTextEx(font, txt, 10, 2);
                    defaultDrawTextEx(txt, .{ .x = x + (opt.width / 2) - (dim.x / 2), .y = y + (opt.height / 2) - (dim.y / 2) }, 10, c.text);
                    color = .blank;
                },
                .mine => {
                    //                    rl.drawRectangleRec(rect, .red);
                    color = .red;
                },
                .empty_cell => {},
            }
        } else {
            if (this.flagged()) {
                rl.drawRectangleRec(rect, .dark_gray);
                const txt = std.fmt.digitToChar(this.flags(), .lower);
                const font = rl.getFontDefault() catch unreachable;
                const dim = rl.measureTextEx(font, &.{ txt }, 10, 2);
                defaultDrawTextEx(&.{ txt }, .{ .x = x + (opt.width / 2) - (dim.x / 2), .y = y + (opt.height / 2) - (dim.y / 2) }, 10, .white);
                color = .blank;
            } else {
                color = c.foreground;
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
    pos: easing.EVector2,

    pub fn init(camera: rl.Camera2D) Camera {
        return .{
            .camera = camera,
            .pos = .init(camera.target),
        };
    }

    pub fn animateShift(this: *Camera, x: f32, y: f32, duration: f32) void {
        const target = this.pos.targetVec();
        this.animateMove(target.x + x, target.y + y, duration);
    }

    pub fn shift(this: *Camera, x: f32, y: f32) void {
        const target = this.pos.targetVec();
        this.move(target.x + x, target.y + y);
    }

    pub fn move(this: *Camera, x: f32, y: f32) void {
        this.pos.set(x, y);
        this.camera.target = this.pos.targetVec();
    }

    pub fn animateMove(this: *Camera, x: f32, y: f32, duration: f32) void {
        this.pos.interpolate(.linear, duration, .init(x, y));
    }

    pub fn tick(this: *Camera, dt: f32) void {
        this.pos.tick(dt);
        this.camera.target = this.pos.toVec2();
    }
};

const Settings = struct {
    keyboard_mode: bool = true,
    invert_mouse_wheel: bool = false,
};

const Highlight = struct {
    pos: IVec2,
    color: rl.Color,
};

const Board = struct {
    const chunk_size = 16;

    pub const Scene = std.array_hash_map.Auto(IVec2, Chunk);
    pub const Chunk = TwoDimensionalList(GridSpace);
    io: std.Io,
    seed: i64,
    scene: Scene,
    chunk_bomb_rate: f32,
    arena: std.heap.ArenaAllocator,
    cursor_pos: IVec2 = .{ .x = 0, .y = 0 },
    camera: *Camera,
    mode: Mode,
    settings: *Settings,
    noise: fast.Noise(f32),
    biome_manager: BiomeManager,
    end_thyself: bool = false,
    dead: bool = false,
    chunks_to_generate: std.ArrayList(IVec2) = .empty,
    highlighted_cells: std.ArrayList(Highlight) = .empty,

    pub const Mode = enum {
        default,
        flag_only,
    };

    pub fn init(gpa: std.mem.Allocator, io: std.Io, chunk_bomb_rate: f32, camera: *Camera, mode: Mode, settings: *Settings, biome_manager: BiomeManager) !Board {
        const seed = std.Io.Timestamp.now(io, .real).toMilliseconds();
        return .{
            .io = io,
            .seed = seed,
            .scene = .empty,
            .chunk_bomb_rate = chunk_bomb_rate,
            .arena = .init(gpa),
            .camera = camera,
            .mode = mode,
            .settings = settings,
            .noise = .{
                .frequency = 0.05,
                .noise_type = .cellular,
                .cellular_distance = .manhattan,
                .cellular_return = .cell_value,
                .cellular_jitter_mod = 1.0,
                .seed = @truncate(seed),
            },
            .biome_manager = biome_manager,
        };
    }

    pub fn deinit(this: Board) void {
        this.arena.deinit();
    }

    pub fn highlightNeighbors(this: *Board, pos: IVec2) !void {
        const cell = this.getPtr(pos.x, pos.y) orelse return;
        if (cell.hidden()) return;
        this.highlighted_cells.clearAndFree(this.arena.allocator());
        var n = cell.neighbors(pos);
        try this.highlighted_cells.ensureTotalCapacity(this.arena.allocator(), n.len);
        while (n.next()) |vec| {
            this.highlighted_cells.appendAssumeCapacity(.{
                .pos = pos.add(vec),
                .color = .white,
            });
        }
    }

    const default_camera_zoom = 1.8719;
    pub fn tick(this: *Board, dt: f32) !void {
        const gpa = this.arena.allocator();
        for (this.chunks_to_generate.items) |vec| {
            if (!this.scene.contains(vec)) {
                try this.scene.put(gpa, vec, try this.generateChunk(vec, this.chunk_bomb_rate));
            }
        }
        this.chunks_to_generate.clearAndFree(this.arena.allocator());
        var clear = false;
        for (this.highlighted_cells.items) |*highlight| {
            const a = highlight.color.normalize().w;
            highlight.color = highlight.color.fade(a - dt);
            if (a <= dt) {
                clear = true;
            }
        }
        if (clear) {
            this.highlighted_cells.clearAndFree(this.arena.allocator());
        }
        const cursor = if (this.settings.keyboard_mode) this.cursor_pos else this.mouseToCell();
        if (this.settings.keyboard_mode) {
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
        } else {
            if (rl.isKeyDown(.a)) {
                this.camera.shift(-200 * dt, 0);
            }
            if (rl.isKeyDown(.d)) {
                this.camera.shift(200 * dt, 0);
            }
            if (rl.isKeyDown(.w)) {
                this.camera.shift(0, -200 * dt);
            }
            if (rl.isKeyDown(.s)) {
                this.camera.shift(0, 200 * dt);
            }

            if (rl.isMouseButtonPressed(.right)) {
                try this.flag(cursor);
                try this.highlightNeighbors(cursor);
            }
            if (rl.isMouseButtonPressed(.left)) blk: {
                if (this.dead) {
                    this.end_thyself = true;
                    break :blk;
                }

                try this.reveal(cursor);
            }
            const mul_vec: rl.Vector2 = if (this.settings.invert_mouse_wheel) .init(-2, -2) else .init(2, 2);
            const wheel = rl.getMouseWheelMoveV().multiply(mul_vec);
            if (!wheel.equals(.zero())) {
                this.camera.shift(wheel.x, wheel.y);
            }
            // TODO: when raylib can do trackpad pinching, add that
        }
        if (rl.isKeyDown(.e)) {
            this.camera.camera.zoom = rl.math.clamp(this.camera.camera.zoom + (this.camera.camera.zoom * 3 * dt), default_camera_zoom - 1.5, 100);
        }
        if (rl.isKeyDown(.q)) {
            this.camera.camera.zoom = rl.math.clamp(this.camera.camera.zoom - (this.camera.camera.zoom * 3 * dt), default_camera_zoom - 1.5, 100);
        }
        if (rl.isKeyPressed(.r)) {
            this.camera.camera.zoom = default_camera_zoom;
        }
        if (rl.isKeyPressed(.space)) blk: {
            if (this.dead) {
                this.end_thyself = true;
                break :blk;
            }
            try this.reveal(cursor);
        }

        if (rl.isKeyPressed(.f) or rl.isKeyPressed(.j)) {
            try this.flag(cursor);
            try this.highlightNeighbors(cursor);
        }

        this.camera.tick(dt);
    }

    fn reveal(this: *Board, pos: IVec2) !void {
        if (this.mode == .flag_only and !pos.eql(.zero)) return;
        const ptr = this.getPtr(pos.x, pos.y) orelse {
            std.log.err("null cell {d} {d}\n", .{ pos.x, pos.y });
            return;
        };
        if (ptr.flagged()) return;
        if (!ptr.hidden() and ptr.* == .number and this.mode != .flag_only) {
            if (try ptr.fullFlagReveal(.{ .x = pos.x, .y = pos.y, .list = this }, pos)) {
                this.dead = true;
            }
        } else {
            const t = try ptr.reveal(.{ .x = pos.x, .y = pos.y, .list = this });
            if (t == .mine) {
                this.dead = true;
            }
        }
    }

    fn flag(this: *Board, pos: IVec2) !void {
        if (this.dead) return;
        const ptr = this.getPtr(pos.x, pos.y) orelse {
            std.log.err("null cell {d} {d}\n", .{ pos.x, pos.y });
            return;
        };
        ptr.flag();
        if (this.mode == .flag_only) {
            var x: i32 = -1;
            loop: while (x <= 1) : (x += 1) {
                var y: i32 = -1;
                while (y <= 1) : (y += 1) {
                    const cell = this.getPtr(pos.x + x, pos.y + y) orelse continue;
                    if (try cell.fullFlagReveal(.{ .x = pos.x + x, .y = pos.y + y, .list = this }, pos.lAdd(x, y))) {
                        this.dead = true;
                        break :loop;
                    }
                }
            }
        }
    }

    pub fn getPositionSeed(this: *Board, pos: IVec2) u64 {
        return @bitCast(this.seed +% @as(i64, @bitCast(pos)));
    }

    pub fn getPositionBomb(this: *Board, pos: IVec2, bomb_rate: f32, max: u8) u8 {
        var prng = std.Random.DefaultPrng.init(this.getPositionSeed(pos));
        const rand = prng.random().float(f32);
        if (rand < bomb_rate) {
            if (rand <= 0) return max;
            return @floor(@min(@divFloor(bomb_rate, rand), max));
        }
        return 0;
    }

    fn generateChunk(this: *Board, pos: IVec2, bomb_rate: f32) !Chunk {
        var chunk = try Chunk.initValued(this.arena.allocator(), chunk_size, chunk_size, .{ .empty_cell = .{ .biome = undefined } });
        const sized = pos.multValue(chunk_size);
        {
            var x: i32 = 0;
            while (x < chunk_size) : (x += 1) {
                var y: i32 = 0;
                while (y < chunk_size) : (y += 1) {
                    const off = sized.lAdd(x, y);
                    const biome = this.cellBiome(off);
                    defer {
                        switch ((chunk.getPtr(x, y) catch unreachable).*) {
                            inline else => |*a| {
                                a.biome = biome;
                            },
                        }
                    }
                    if (off.lEql(0, 0)) continue;
                    const bomb = this.getPositionBomb(off, bomb_rate * biome.rateMod(), biome.maxBombs());
                    if (bomb > 0) {
                        chunk.silentSet(x, y, .{ .mine = .{ .biome = biome, .value = bomb } });
                    }
                }
            }
        }
        var x: i32 = 0;
        while (x < chunk_size) : (x += 1) {
            var y: i32 = 0;
            while (y < chunk_size) : (y += 1) {
                const cell = try chunk.get(x, y);
                if (cell == .empty_cell) {
                    var count: u8 = 0;
                    var n = cell.neighbors(sized.lAdd(x, y));
                    while (n.next()) |vec| {
                        const abs = vec.lAdd(x, y);
                        const n_biome = this.cellBiome(sized.add(abs));
                        const rate = if (abs.add(sized).floorDivValue(chunk_size).eql(.zero) and this.mode == .flag_only) -1 else this.chunk_bomb_rate;
                        const bombs = this.getPositionBomb(sized.add(abs), rate * n_biome.rateMod(), n_biome.maxBombs());
                        if (bombs > 0) {
                            count += bombs;
                        }
                    }
                    if (count > 0) {
                        chunk.silentSet(x, y, .{ .number = .{ .value = count, .biome = cell.biome() } });
                    }
                }
            }
        }
        return chunk;
    }

    fn cellBiome(this: *Board, pos: IVec2) Biome {
        const n = this.noise.genNoise2D(@floatFromInt(pos.x), @floatFromInt(pos.y));
        return this.biome_manager.fromValue(n);
    }

    pub fn setup(this: *Board) !void {
        var chunk_x: i32 = -5;
        while (chunk_x < 5) : (chunk_x += 1) {
            var chunk_y: i32 = -5;
            while (chunk_y < 5) : (chunk_y += 1) {
                const is_flag = this.mode == .flag_only and chunk_x == 0 and chunk_y == 0;
                const chunk = try this.generateChunk(.{ .x = chunk_x, .y = chunk_y }, if (is_flag) -1 else this.chunk_bomb_rate);
                this.scene.put(this.arena.allocator(), .{ .x = chunk_x, .y = chunk_y }, chunk) catch @panic("put failed");
            }
        }
    }

    fn mouseToCell(this: *Board) IVec2 {
        const cursor_screen = rl.getMousePosition();
        const cursor = rl.getScreenToWorld2D(cursor_screen, this.camera.camera).divide(.init(20, 20));
        return .{ .x = @floor(cursor.x), .y = @floor(cursor.y) };
    }

    fn checkAndQueueAdjacentChunks(this: *Board, chunk: IVec2) !void {
        var off_x: i32 = -1;
        while (off_x <= 1) : (off_x += 1) {
            var off_y: i32 = -1;
            while (off_y <= 1) : (off_y += 1) {
                const chk = chunk.lAdd(off_x, off_y);
                if (!this.scene.contains(chk)) {
                    try this.chunks_to_generate.append(this.arena.allocator(), chk);
                }
            }
        }
    }

    pub fn draw(this: *Board) !void {
        const cursor = if (this.settings.keyboard_mode) this.cursor_pos else this.mouseToCell();
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
                    cell.draw(.{ .x = x, .y = y, .width = 20, .height = 20, .hovering = cursor.lEql(x, y) });
                }
            }
            for (this.highlighted_cells.items) |highlight| {
                const real = highlight.pos.multValue(20);
                rl.drawRectangleRec(.init(@floatFromInt(real.x), @floatFromInt(real.y), 20, 20), highlight.color);
            }
            const tl_chunk = tl_vec.floorDivValue(chunk_size);
            const br_chunk = br_vec.floorDivValue(chunk_size);
            try this.checkAndQueueAdjacentChunks(tl_chunk);
            try this.checkAndQueueAdjacentChunks(tl_chunk.minComp(br_chunk));
            try this.checkAndQueueAdjacentChunks(tl_chunk.maxComp(br_chunk));
            try this.checkAndQueueAdjacentChunks(br_chunk);
        }
        var buf: [64]u8 = undefined;
        const txt = try std.fmt.bufPrintZ(&buf, "Cursor: {d} {d}", .{ cursor.x, cursor.y });
        rl.drawText(txt, 0, 30, 24, .white);
        const chunk_pos = cursor.floorDivValue(chunk_size);
        const chunk_text = try std.fmt.bufPrintZ(&buf, "Chunk: {d} {d}", .{ chunk_pos.x, chunk_pos.y });
        rl.drawText(chunk_text, 0, 50, 24, .white);
        if (this.dead) {
            const screen_width = rl.getScreenWidth();
            const str = "You are dead";
            const default = try rl.getFontDefault();
            const width = rl.measureTextEx(default, str, 64, @floatFromInt(default.glyphPadding));
            rl.drawText(str, @divFloor(screen_width, 2) - @as(i32, @trunc(width.x / 2)), 128, 64, .white);
            const str2 = "Click/Space to restart";
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

fn SelectionMenu(comptime Manager: type, comptime Enum: type, comptime func: *const fn (*Manager, Enum) void) type {
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
        // added back because it feels weird to not be able to select a different option with the mouse while another menu is open
        accept_input: bool,

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
            node.accept_input = true;
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
            if (!this.accept_input) return .propagate;
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
    const MainMenu = SelectionMenu(MenuManager, MainOptions, submitMainMenu);
    pub const MainOptions = enum {
        Resume,
        Restart,
        Mode,
        Settings,
        Exit,
    };
    const ModeMenu = SelectionMenu(MenuManager, ModeOptions, submitModeMenu);
    pub const ModeOptions = enum {
        Default,
        @"Flags Only",
        Back,
    };
    // TODO: add actual settings ui entries
    const SettingsMenu = SelectionMenu(MenuManager, SettingsOptions, submitSettingsMenu);
    const SettingsOptions = enum {
        @"Keyboard Mode",
        @"Invert Scroll",
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
    settings_menu: ?NodePair(SettingsMenu),
    exit_ptr: *bool,
    restart_ptr: *bool,
    target_mode_ptr: *Board.Mode,
    settings: *Settings,

    pub fn init(gpa: std.mem.Allocator, exit_ptr: *bool, restart_ptr: *bool, target_mode_ptr: *Board.Mode, settings: *Settings) !*MenuManager {
        const node = try gpa.create(MenuManager);
        node.gpa = gpa;
        node.layout = try ui.LayoutNode.init(gpa, 12, .horizontal, .start);
        node.layout_node = try node.layout.toNode();
        node.main_menu = null;
        node.mode_menu = null;
        node.settings_menu = null;
        node.exit_ptr = exit_ptr;
        node.restart_ptr = restart_ptr;
        node.target_mode_ptr = target_mode_ptr;
        node.settings = settings;
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
        if (this.main_menu == null) unreachable;
        if (this.settings_menu != null) unreachable;
        this.mode_menu = try .init(try ModeMenu.init(this.gpa, this));
        try this.layout_node.addChild(this.mode_menu.?.node);
        try this.layout_node.recalculateNodeGraphSize();
        this.main_menu.?.manager.accept_input = false;
        //this.main_menu.?.node.frozen = true;
    }

    pub fn openSettings(this: *MenuManager) !void {
        if (this.settings_menu != null) return;
        if (this.main_menu == null) unreachable;
        if (this.mode_menu != null) unreachable;
        this.settings_menu = try .init(try SettingsMenu.init(this.gpa, this));
        try this.layout_node.addChild(this.settings_menu.?.node);
        try this.layout_node.recalculateNodeGraphSize();
        this.main_menu.?.manager.accept_input = false;
        //this.main_menu.?.node.frozen = true;
    }

    pub fn close(this: *MenuManager) !void {
        if (this.main_menu) |m| {
            if (m.node.parent) |p| {
                try m.node.setId("llllldwijaiwa");
                if (!p.removeChildId("llllldwijaiwa")) unreachable;
            } else {
                m.node.deinit();
            }
            this.main_menu = null;
        }
        if (this.mode_menu) |m| {
            if (m.node.parent) |p| {
                try m.node.setId("llllldwijaiwa");
                if (!p.removeChildId("llllldwijaiwa")) unreachable;
            } else {
                m.node.deinit();
            }
            this.mode_menu = null;
        }
        if (this.settings_menu) |m| {
            if (m.node.parent) |p| {
                try m.node.setId("llllldwijaiwa");
                if (!p.removeChildId("llllldwijaiwa")) unreachable;
            } else {
                m.node.deinit();
            }
            this.settings_menu = null;
        }

        try this.layout_node.recalculateNodeGraphSize();
    }

    pub fn closeMode(this: *MenuManager) !void {
        if (this.mode_menu) |m| {
            if (m.node.parent) |p| {
                try m.node.setId("llllldwijaiwa");
                if (!p.removeChildId("llllldwijaiwa")) unreachable;
            } else {
                m.node.deinit();
            }
            this.mode_menu = null;
        }
        this.main_menu.?.manager.accept_input = true;
        try this.layout_node.recalculateNodeGraphSize();
    }

    pub fn closeSettings(this: *MenuManager) !void {
        if (this.settings_menu) |m| {
            if (m.node.parent) |p| {
                try m.node.setId("llllldwijaiwa");
                if (!p.removeChildId("llllldwijaiwa")) unreachable;
            } else {
                m.node.deinit();
            }
            this.settings_menu = null;
        }
        this.main_menu.?.manager.accept_input = true;
        try this.layout_node.recalculateNodeGraphSize();
    }

    fn submitMainMenu(this: *MenuManager, active: MainOptions) void {
        if (this.settings_menu) |_| this.closeSettings() catch |err| std.debug.panicExtra(null, "settings close failure {any}", .{err});
        if (this.mode_menu) |_| this.closeMode() catch |err| std.debug.panicExtra(null, "mode close failure {any}", .{err});
        switch (active) {
            .Resume => this.close() catch |err| std.debug.panicExtra(null, "menu close failure {any}", .{err}),
            .Restart => {
                this.restart_ptr.* = true;
                this.close() catch |err| std.debug.panicExtra(null, "menu close failure {any}", .{err});
            },
            .Mode => this.openMode() catch |err| std.debug.panicExtra(null, "mode open failure {any}", .{err}),
            .Settings => this.openSettings() catch |err| std.debug.panicExtra(null, "settings open failure {any}", .{err}),
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

    fn submitSettingsMenu(this: *MenuManager, active: SettingsOptions) void {
        switch (active) {
            .@"Keyboard Mode" => {
                this.settings.keyboard_mode = !this.settings.keyboard_mode;
            },
            .@"Invert Scroll" => {
                this.settings.invert_mouse_wheel = !this.settings.invert_mouse_wheel;
            },
            .Back => {
                this.closeSettings() catch |err| std.debug.panicExtra(null, "settings close failure {any}", .{err});
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

const CellColors = struct {
    foreground: rl.Color,
    background: rl.Color,
    text: rl.Color = .white,
};

const BiomeManager = struct {
    periods: []Period,
    default: Biome = .default,

    pub fn init(gpa: std.mem.Allocator, periods: []const Period, default: Biome) !BiomeManager {
        var list = try std.ArrayList(i8).initCapacity(gpa, periods.len * 2);
        defer list.deinit(gpa);
        for (periods) |p| {
            for (list.items) |i| {
                if (p.lower == i) {
                    std.log.err("Overlapping periods {d} and {d}", .{ i, i });
                    return error.OverlappingPeriods;
                }
                if (p.upper == i) {
                    std.log.err("Overlapping periods {d} and {d}", .{ i, i });
                    return error.OverlappingPeriods;
                }
                list.appendAssumeCapacity(p.lower);
                list.appendAssumeCapacity(p.upper);
            }
        }
        return .{
            .periods = try gpa.dupe(Period, periods),
            .default = default,
        };
    }

    pub fn initDefault(gpa: std.mem.Allocator) !BiomeManager {
        return init(gpa, &.{
            .init(21, 100, .default),
            .init(1, 20, .high_rate),
            .init(-19, 0, .two_bombs),
            .init(-49, -20, .three_bombs),
            .init(-69, -50, .cardinal),
            .init(-89, -70, .line),
        }, .default);
    }

    pub fn deinit(this: BiomeManager, gpa: std.mem.Allocator) void {
        gpa.free(this.periods);
    }

    pub fn fromValue(this: BiomeManager, value: f32) Biome {
        const int: i8 = @floor(value * 100);
        for (this.periods) |p| {
            if (int >= p.lower and int <= p.upper) return p.biome;
        }
        return this.default;
    }

    pub const Period = struct {
        biome: Biome,
        lower: i8,
        upper: i8,

        pub fn init(lower: i8, upper: i8, biome: Biome) Period {
            return .{ .lower = lower, .upper = upper, .biome = biome };
        }
    };
};

const Biome = enum {
    default,
    high_rate,
    two_bombs,
    three_bombs,
    cardinal,
    line,

    pub fn fromValue(value: f32) Biome {
        return switch (@as(i8, @floor(value * 100))) {
            21...100 => .default,
            1...20 => .high_rate,
            -19...0 => .two_bombs,
            -49...-20 => .three_bombs,
            -69...-50 => .cardinal,
            -89...-70 => .line,
            else => .default,
        };
    }

    pub fn neighbors(b: Biome, pos: IVec2) GridSpace.Neighbors {
        switch (b) {
            .default => {
                comptime var arr: [3 * 3 - 1]IVec2 = undefined;
                comptime {
                    var i = 0;
                    var x = -1;
                    while (x <= 1) : (x += 1) {
                        var y = -1;
                        while (y <= 1) : (y += 1) {
                            if (x == 0 and y == 0) continue;
                            arr[i] = .{ .x = x, .y = y };
                            i += 1;
                        }
                    }
                }
                return comptime .init(&arr);
            },
            .cardinal => {
                return .init(&.{
                    .{ .x = 0, .y = -1 },
                    .{ .x = 0, .y = 1 },
                    .{ .x = -1, .y = 0 },
                    .{ .x = 1, .y = 0 },
                });
            },
            .line => {
                if (pos.remValue(2).abs().lEql(1, 0) or pos.remValue(2).abs().lEql(0, 1)) {
                    return .init(&.{
                        .{ .x = -1, .y = 0 },
                        .{ .x = 1, .y = 0 },
                    });
                } else {
                    return .init(&.{
                        .{ .x = 0, .y = -1 },
                        .{ .x = 0, .y = 1 },
                    });
                }
                return .init(&.{
                    .{ .x = -1, .y = -1 },
                    .{ .x = 1, .y = 1 },
                    .{ .x = -1, .y = 1 },
                    .{ .x = 1, .y = -1 },
                });
            },
            else => return Biome.default.neighbors(pos),
        }
    }

    pub fn colors(b: Biome, pos: IVec2) CellColors {
        switch (b) {
            .default => return .{ .background = .fromInt(tertiary_color), .foreground = .fromInt(primary_color) },
            .high_rate => return .{ .background = .fromInt(0x4a2331ff), .foreground = .fromInt(0xb53462ff) },
            .cardinal => return .{ .background = .fromInt(0x383c37ff), .foreground = .fromInt(0xafc99dff) },
            .line => {
                if (pos.remValue(2).abs().lEql(1, 0) or pos.remValue(2).abs().lEql(0, 1)) {
                    return .{ .background = .fromInt(0x333333ff), .foreground = .fromInt(0xddddddff) };
                } else {
                    return .{ .background = .fromInt(0x111111ff), .foreground = .fromInt(0xbbbbbbff) };
                }
            },
            .two_bombs => return .{ .background = .fromInt(0x1d4052ff), .foreground = .fromInt(0x42a3cdff) },
            .three_bombs => return .{ .background = .fromInt(0x332c7dff), .foreground = .fromInt(0xa140cfff) },
        }
    }

    pub fn maxBombs(b: Biome) u8 {
        return switch (b) {
            .two_bombs => 2,
            .three_bombs => 3,
            else => 1,
        };
    }

    pub fn rateMod(b: Biome) f32 {
        return switch (b) {
            .high_rate => 1.4,
            else => 1,
        };
    }
};

pub fn noiseVisual(init: std.process.Init) !void {
    const seed: i32 = @truncate(std.Io.Timestamp.now(init.io, .real).toMilliseconds());
    const n = fast.Noise(f32){
        .frequency = 0.001,
        .noise_type = .cellular,
        .cellular_distance = .manhattan,
        .cellular_return = .cell_value,
        .cellular_jitter_mod = 1.0,
        .seed = seed,
    };
    const screen_width = 1080;
    const screen_height = 720;
    rl.initWindow(screen_width, screen_height, "noise");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    const tex = try rl.RenderTexture2D.init(3 * screen_width, 3 * screen_height);
    std.log.debug("{d}", .{n.genNoise2D(0, 0)});
    defer tex.unload();
    tex.begin();
    rl.clearBackground(.black);
    for (0..(20 * screen_width) / 20) |x| {
        for (0..(20 * screen_height) / 20) |y| {
            const value = n.genNoise2D(@floatFromInt(x * 20), @floatFromInt(y * 20));
            const color: rl.Color = switch (@as(i8, @floor(value * 100))) {
                21...100 => .white,
                1...20 => .red,
                -19...0 => .blue,
                -49...-20 => .green,
                -69...-50 => .pink,
                -89...-70 => .purple,
                else => .black,
            };
            rl.drawRectangle(@intCast(x * 20), @intCast(y * 20), 20, 20, color);
        }
    }
    tex.end();

    std.log.debug("{d}", .{n.genNoise2D(0, 0)});
    var camera = rl.Camera2D{
        .offset = .init(screen_width / 2, screen_height / 2),
        .rotation = 0,
        .target = .zero(),
        .zoom = 1,
    };
    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        if (rl.isKeyDown(.q)) {
            camera.zoom -= 0.05;
        }
        if (rl.isKeyDown(.e)) {
            camera.zoom += 0.05;
        }
        if (rl.isKeyDown(.a)) {
            camera.target.x += -200 * dt;
        }
        if (rl.isKeyDown(.d)) {
            camera.target.x += 200 * dt;
        }
        if (rl.isKeyDown(.w)) {
            camera.target.y += -200 * dt;
        }
        if (rl.isKeyDown(.s)) {
            camera.target.y += 200 * dt;
        }

        const c = rl.getMousePosition();
        const x = rl.getMouseX();
        const y = rl.getMouseY();
        const v = n.genNoise2D(@floatFromInt(x), @floatFromInt(y));
        const fmt = try std.fmt.allocPrintSentinel(init.gpa, "{d}", .{v}, 0);
        defer init.gpa.free(fmt);
        rl.beginDrawing();
        camera.begin();
        rl.clearBackground(.black);
        rl.drawTexturePro(tex.texture, .init(0, 0, 3 * screen_width, -3 * screen_height), .init(0, 0, 3 * screen_width, 3 * screen_height), .init(0, 0), 0, .white);
        rl.drawRectangleRec(.init(c.x, c.y, 3, -3), .green);
        camera.end();
        rl.drawText(fmt, 0, 40, 24, .green);
        rl.drawFPS(0, 0);
        rl.endDrawing();
    }
}
pub fn main(init: std.process.Init) !void {
    var screen_width: f32 = 1080;
    var screen_height: f32 = 720;

    rl.initWindow(@floor(screen_width), @floor(screen_height), "Minesweeeeeper");
    rl.setWindowState(.{ .window_resizable = true });
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

    var settings: Settings = .{};

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
    const menu = try MenuManager.init(init.gpa, &should_exit, &should_restart, &target_mode, &settings);
    const menu_node = try menu.toNode();
    menu_node.space.offset.y = 30;
    try root_node.addChild(menu_node);

    try inspector.setRoot(root_node);

    var keys_pressed: std.ArrayList(rl.KeyboardKey) = .empty;
    defer keys_pressed.deinit(init.gpa);

    const biome_manager = try BiomeManager.initDefault(init.gpa);
    defer biome_manager.deinit(init.gpa);

    while (!(should_exit or rl.windowShouldClose())) {
        should_restart = false;
        camera.move(10, 10);
        var board = try Board.init(init.gpa, init.io, 0.2, &camera, target_mode, &settings, biome_manager);
        defer board.deinit();
        try board.setup();
        var last_cursor = inspector.translate(rl.getMousePosition().divide(root.true_size).multiply(root.screen_size));
        while (!(should_exit or board.end_thyself or should_restart or rl.windowShouldClose())) {
            if (rl.isWindowResized()) {
                screen_width = @floatFromInt(rl.getScreenWidth());
                screen_height = @floatFromInt(rl.getScreenHeight());
                try inspector.resize(screen_width, screen_height);
                root.screen_size = .init(screen_width, screen_height);
                root.true_size = .init(screen_width, screen_height);
                camera.camera.offset = .{ .x = screen_width / 2, .y = screen_height / 2 };
            }
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
                // this is here because it stalls for a frame after endDrawing, so if you use mouse controls you wont immediately
                // click whatever your mouse is hovering over
                rl.beginDrawing();
                rl.endDrawing();
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
