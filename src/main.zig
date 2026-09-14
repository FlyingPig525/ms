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
        if (this.* == .number) {
            const value = this.number.value;
            var flagged_cells: u8 = 0;
            {
                comptime var x = -1;
                inline while (x <= 1) : (x += 1) {
                    comptime var y = -1;
                    inline while (y <= 1) : (y += 1) {
                        if (info.list.get(info.x + x, info.y + y)) |cell| {
                            if (cell.flagged()) flagged_cells += 1;
                        }
                    }
                }
            }
            if (flagged_cells >= value) {
                comptime var x = -1;
                inline while (x <= 1) : (x += 1) {
                    comptime var y = -1;
                    inline while (y <= 1) : (y += 1) {
                        if (info.list.getPtr(info.x + x, info.y + y)) |cell| blk: {
                            if (cell.flagged()) break :blk;
                            const t = try cell.reveal(.{ .x = info.x + x, .y = info.y + y, .list = info.list });
                            if (t == .mine) return true;
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
    end_thyself: bool = false,

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
            this.camera.camera.zoom = rl.math.clamp(this.camera.camera.zoom * 1.1, 1.8719, 100);
        }
        if (rl.isKeyDown(.q)) {
            this.camera.camera.zoom = rl.math.clamp(this.camera.camera.zoom * 0.9, 1.8719, 100);
        }
        if (rl.isKeyPressed(.r)) {
            this.camera.camera.zoom = 1.8719;
        }

        if (rl.isKeyPressed(.t)) {
            std.log.debug("{d}", .{this.camera.camera.zoom});
        }

        if (rl.isKeyPressed(.space)) blk: {
            const ptr = this.getPtr(this.cursor_pos.x, this.cursor_pos.y) orelse {
                std.debug.print("null cell {d} {d}\n", .{ this.cursor_pos.x, this.cursor_pos.y });
                break :blk;
            };
            if (ptr.flagged()) break :blk;
            if (!ptr.hidden() and ptr.* == .number) {
                if (try ptr.fullFlagReveal(.{ .x = this.cursor_pos.x, .y = this.cursor_pos.y, .list = this })) {
                    this.end_thyself = true;
                }
            } else {
                const t = try ptr.reveal(.{ .x = this.cursor_pos.x, .y = this.cursor_pos.y, .list = this });
                if (t == .mine) {
                    this.end_thyself = true;
                }
            }
        }

        if (rl.isKeyPressed(.f) or rl.isKeyPressed(.j)) blk: {
            const ptr = this.getPtr(this.cursor_pos.x, this.cursor_pos.y) orelse {
                std.debug.print("null cell {d} {d}\n", .{ this.cursor_pos.x, this.cursor_pos.y });
                break :blk;
            };
            ptr.toggleFlag();
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
                this.scene.put(this.arena.allocator(), .{ .x = chunk_x, .y = chunk_y }, chunk) catch @panic("put failed");
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

            const camera_chunk = this.cursor_pos.floorDivValue(chunk_size);
            const center_x: i32 = camera_chunk.x;
            const center_y: i32 = camera_chunk.y;
            var chunk_x = center_x - 1;
            while (chunk_x <= center_x + 1) : (chunk_x += 1) {
                var chunk_y = center_y - 1;
                while (chunk_y <= center_y + 1) : (chunk_y += 1) {
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

pub const MenuManager = struct {
    entry: Entry,
    gpa: std.mem.Allocator,
    in_menu: bool,
    quit_flag: *bool,
    restart_flag: *bool,
    layout: *ui.LayoutNode,
    layout_node: *ui.Node,
    res: *EntryNode,
    res_node: *ui.Node,
    restart: *EntryNode,
    restart_node: *ui.Node,
    exit: *EntryNode,
    exit_node: *ui.Node,

    pub const Entry = enum(u8) {
        res,
        restart,
        exit,
    };

    pub const EntryNode = struct {
        gpa: std.mem.Allocator,
        text: *ui.TextNode,
        text_node: *ui.Node,
        rect: *ui.RectNode,
        rect_node: *ui.Node,
        selected: bool,

        const entry_vtable: ui.Node.VTable = .{
            .deinit = ui.Node.VTable.basicOpaqueDeinit(EntryNode),
            .calculate_size = calculateSize,
            .type_info = ui.Node.VTable.basicTypeInfo(EntryNode),
        };

        pub fn init(gpa: std.mem.Allocator, text: [:0]const u8) !*EntryNode {
            const node = try gpa.create(EntryNode);
            node.gpa = gpa;
            node.text = try ui.TextNode.initDefault(gpa, text, 24, .white);
            node.text_node = try node.text.toNode();
            node.rect = try ui.RectNode.init(gpa, .blank);
            node.rect_node = try node.rect.toNode();
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
        fn calculateSize(ptr: *anyopaque, _: *ui.Node) !rl.Vector2 {
            const this: *EntryNode = @ptrCast(@alignCast(ptr));
            try this.text_node.calculateSize();
            this.rect_node.space.size.y = this.text_node.space.size.y;
            return this.text_node.space.size.add(.init(12, 0));
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

    pub fn init(gpa: std.mem.Allocator, quit_ptr: *bool, restart_ptr: *bool) !*MenuManager {
        const node = try gpa.create(MenuManager);
        node.entry = .res;
        node.gpa = gpa;
        node.in_menu = false;
        node.quit_flag = quit_ptr;
        node.restart_flag = restart_ptr;
        node.layout = try ui.LayoutNode.init(gpa, 12, .vertical, .start);
        node.layout_node = try node.layout.toNode();
        node.res = try EntryNode.init(gpa, "Resume");
        node.res.select();
        node.res_node = try node.res.toNode();
        node.res_node.space.offset.x = 12;
        try node.layout_node.addChild(node.res_node);

        node.restart = try EntryNode.init(gpa, "Restart");
        node.restart_node = try node.restart.toNode();
        node.restart_node.space.offset.x = 12;
        try node.layout_node.addChild(node.restart_node);

        node.exit = try EntryNode.init(gpa, "Exit");
        node.exit_node = try node.exit.toNode();
        node.exit_node.space.offset.x = 12;
        try node.layout_node.addChild(node.exit_node);

        node.updateNodes();
        return node;
    }

    pub fn deinit(this: *MenuManager) void {
        this.gpa.destroy(this);
    }


    const vtable: ui.Node.VTable = .{
        .deinit = ui.Node.VTable.basicOpaqueDeinit(MenuManager),
        .on_input = onInput,
        .type_info = ui.Node.VTable.basicTypeInfo(MenuManager)
    };

    fn onInput(ptr: *anyopaque, _: *ui.Node, key: rl.KeyboardKey) !ui.Node.Propagation {
        const this: *MenuManager = @ptrCast(@alignCast(ptr));
        switch (key) {
            .j => this.entry = meta.nextEnumValueWrap(this.entry),
            .k => this.entry = meta.prevEnumValueWrap(this.entry),
            .space, .enter => {
                switch (this.entry) {
                    .res => {
                        this.close();
                    },
                    .restart => {
                        this.restart_flag.* = true;
                        this.close();
                    },
                    .exit => {
                        this.quit_flag.* = true;
                    },
                }
            },
            else => return .propagate,
        }
        this.updateNodes();
        return .dont_propagate;
    }

    fn close(this: *MenuManager) void {
        this.in_menu = false;
        this.entry = @enumFromInt(0);
    }

    fn updateNodes(this: *MenuManager) void {
        this.res.deselect();
        this.restart.deselect();
        this.exit.deselect();
        switch (this.entry) {
            .res => this.res.select(),
            .restart => this.restart.select(),
            .exit => this.exit.select(),
        }
    }

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
    const menu = try MenuManager.init(init.gpa, &should_exit, &should_restart);
    const menu_node = try menu.toNode();
    menu_node.space.offset.y = 30;
    try root_node.addChild(menu_node);
    try inspector.setRoot(root_node);

    //    var menu_data = ui.Menu.init(&.{
    //        try .init(init.gpa, "Resume", resumeFromMenu),
    //        try .init(init.gpa, "Exit", exitFromMenu),
    //    });
    //    defer menu_data.deinit(init.gpa);
    while (!(should_exit or rl.windowShouldClose())) {
        should_restart = false;
        camera.move(10, 10);
        var board = try Board.init(init.gpa, 50, &camera);
        defer board.deinit();
        try board.setup(init.io);
        while (!(should_exit or board.end_thyself or should_restart or rl.windowShouldClose())) {
            if (rl.isKeyDown(.left_shift) and rl.isKeyPressed(.escape)) {
                should_exit = true;
                break;
            }
            if (rl.isKeyPressed(.escape)) {
                menu.in_menu = !menu.in_menu;
            }
            if (rl.isKeyPressed(.p)) {
                inspector.is_open = !inspector.is_open;
            }
            if (!menu.in_menu) {
                try board.tick();
            } else {
                while (iterateKeysPressed()) |key| {
                    try root_node.onInput(key);
                }
                try root_node.tick(rl.getFrameTime());
            }
            rl.beginDrawing();
            defer rl.endDrawing();
            {
                inspector.beginDraw();
                defer inspector.endDraw();
                rl.clearBackground(.black);
                if (!menu.in_menu) {
                    try board.draw();
                } else {
                    try root_node.draw();
                }
                rl.drawFPS(0, 0);
            }
            try inspector.draw();
        }
        var cont = false;
        while (!(should_exit or cont or should_restart or rl.windowShouldClose())) {
            if (rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) {
                cont = true;
            }
            rl.beginDrawing();
            defer rl.endDrawing();
            rl.clearBackground(.black);

            rl.drawText("you suck", 0, 0, 50, .white);
        }
    }
}
