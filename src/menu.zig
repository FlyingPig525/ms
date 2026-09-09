const std = @import("std");
const rl = @import("raylib");

pub const Menu = struct {
    cursor: usize = 0,
    items: []const MenuItem,
    exit: bool = false,

    pub const MenuItem = struct {
        pub const SelectAction = *const fn (*Menu) void;
        label: [:0]const u8,
        action: SelectAction,

        pub fn init(gpa: std.mem.Allocator, label: []const u8, action: SelectAction) !MenuItem {
            const l = try gpa.dupeZ(u8, label);
            return .{
                .label = l,
                .action = action,
            };
        }
        pub fn deinit(this: MenuItem, gpa: std.mem.Allocator) void {
            gpa.free(this.label);
        }

        pub fn draw(this: MenuItem, selected: bool, x: i32, y: i32) void {
            rl.drawText(this.label, x, y, 32, if (selected) .light_gray else .white);
        }

        pub fn select(this: MenuItem, menu: *Menu) void {
            this.action(menu);
        }
    };

    pub fn init(items: []const MenuItem) Menu {
        return .{
            .items = items,
        };
    }

    pub fn deinit(this: Menu, gpa: std.mem.Allocator) void {
        for (this.items) |item| {
            item.deinit(gpa);
        }
    }

    pub fn tick(this: *Menu) void {
        if (rl.isKeyPressed(.j)) {
            this.cursor = std.math.clamp(this.cursor + 1, 0, this.items.len - 1);
        }
        if (rl.isKeyPressed(.k)) blk: {
            if (this.cursor == 0) break :blk;
            this.cursor = std.math.clamp(this.cursor - 1, 0, this.items.len - 1);
        }
        if (rl.isKeyPressed(.space)) {
            this.items[this.cursor].select(this);
        }
    }

    pub fn draw(this: Menu) void {
        for (this.items, 0..) |item, _i| {
            const i: i32 = @intCast(_i);
            const selected = _i == this.cursor;
            item.draw(selected, if (selected) 15 else 5, 5 + (37 * i));
        }
    }
};

pub const Node = struct {
    self: *anyopaque,
    vtable: *const VTable,
    tools: *const DrawTools,
    space: Space,
    children: std.ArrayList(*Node),
    parent: *Node,
    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator, self: *anyopaque, space: Space, vtable: *const VTable) !*Node {
        var node = try gpa.create(Node);
        node.self = self;
        node.vtable = vtable;
        node.tools = &.default;
        node.space = space;
        node.children = .empty;
        node.gpa = gpa;
        return node;
    }

    pub fn deinit(this: *Node) void {
        for (this.children.items) |child| {
            child.deinit();
        }
        this.vtable.deinit(this.self);
        this.children.deinit(this.gpa);
        this.gpa.destroy(this);
    }

    pub fn addChild(this: *Node, child: *Node) !void {
        try this.children.append(this.gpa, child);
        child.parent = this;
    }

    pub fn removeChild(this: *Node, i: usize) void {
        const child = this.children.orderedRemove(i);
        child.deinit();
    }

    pub const Space = struct {
        offset: rl.Vector2,
        size: rl.Vector2,

        pub fn initSize(width: f32, height: f32) Space {
            return .{
                .offset = .init(0, 0),
                .size = .init(width, height),
            };
        }
    };

    pub const DrawTools = struct {
        rect: *const fn (node: *Node, rect: rl.Rectangle, color: rl.Color) void,
        rect_lines: *const fn (node: *Node, rect: rl.Rectangle, thickness: f32, color: rl.Color) void,
        line: *const fn (node: *Node, start: rl.Vector2, end: rl.Vector2, thickness: f32, color: rl.Color) void,
        circle: *const fn (node: *Node, center: rl.Vector2, radius: f32, color: rl.Color) void,
        text: *const fn (node: *Node, font: rl.Font, text: [:0]const u8, pos: rl.Vector2, font_size: f32, spacing: f32, tint: rl.Color) void,

        pub const default: DrawTools = .{
            .rect = bubbleRect,
            .rect_lines = bubbleRectLines,
            .line = bubbleLine,
            .circle = bubbleCircle,
            .text = bubbleText,
        };

        fn bubbleText(this: *Node, font: rl.Font, text: [:0]const u8, pos: rl.Vector2, font_size: f32, spacing: f32, tint: rl.Color) void {
            const true_pos = pos.add(this.space.offset);
            this.parent.tools.text(this.parent, font, text, true_pos, font_size, spacing, tint);
        }

        /// Bubble versions of the node draw functions draw to the absolute space of this node.
        ///
        /// For example, if the node has a size `.{ .x = 128, .y = 64 }`, the center would be `.{ .x = 64, .y = 32 }`.
        fn bubbleRect(this: *Node, rect: rl.Rectangle, color: rl.Color) void {
            const true_rect: rl.Rectangle = .{
                .x = rect.x + this.space.offset.x,
                .y = rect.y + this.space.offset.y,
                .width = rect.width,
                .height = rect.height,
            };
            this.parent.tools.rect(this.parent, true_rect, color);
        }

        fn bubbleRectLines(this: *Node, rect: rl.Rectangle, thickness: f32, color: rl.Color) void {
            const true_rect: rl.Rectangle = .{
                .x = rect.x + this.space.offset.x,
                .y = rect.y + this.space.offset.y,
                .width = rect.width,
                .height = rect.height,
            };
            this.parent.tools.rect_lines(this.parent, true_rect, thickness, color);
        }

        fn bubbleLine(this: *Node, start: rl.Vector2, end: rl.Vector2, thickness: f32, color: rl.Color) void {
            const true_start = start.add(this.space.offset);
            const true_end = end.add(this.space.offset);
            this.parent.tools.line(this.parent, true_start, true_end, thickness, color);
        }

        fn bubbleCircle(this: *Node, center: rl.Vector2, radius: f32, color: rl.Color) void {
            const true_center = center.add(this.space.offset);
            this.parent.tools.circle(this.parent, true_center, radius, color);
        }
    };

    /// Draws a rectangle in the space of this node
    ///
    /// Values should be expressed as a fraction of that value of this node. For example, to draw to the center of this node,
    /// set the x and y to 0.5
    pub fn drawRect(this: *Node, rect: rl.Rectangle, color: rl.Color) void {
        const true_rect: rl.Rectangle = .{
            .x = (rect.x * this.space.size.x) + this.space.offset.x,
            .y = (rect.y * this.space.size.y) + this.space.offset.y,
            .width = rect.width * this.space.size.x,
            .height = rect.height * this.space.size.y,
        };
        this.parent.tools.rect(this.parent, true_rect, color);
    }

    /// Draws a rectangle outline in the space of this node
    ///
    /// Values, except thickness, should be expressed as a fraction of that value of this node. For example, to draw
    /// to the center of this node, set the x and y to 0.5
    pub fn drawRectLines(this: *Node, rect: rl.Rectangle, thickness: f32, color: rl.Color) void {
        const true_rect: rl.Rectangle = .{
            .x = rect.x * this.space.offset.x,
            .y = rect.y * this.space.offset.y,
            .width = rect.width * this.space.size.x,
            .height = rect.height * this.space.size.y,
        };
        this.parent.tools.rect_lines(this.parent, true_rect, thickness, color);
    }

    /// Draws a line in the space of this node
    ///
    /// Values, except thickness, should be expressed as a fraction of that value of this node. For example, to draw
    /// to the center of this node, set the x and y to 0.5
    pub fn drawLine(this: *Node, start: rl.Vector2, end: rl.Vector2, thickness: f32, color: rl.Color) void {
        const true_start = start.multiply(this.space.offset);
        const true_end = end.multiply(this.space.offset);
        this.parent.tools.line(this.parent, true_start, true_end, thickness, color);
    }

    /// Draws a circle in the space of this node
    ///
    /// Values, except for radius, should be expressed as a fraction of that value of this node. For example, to draw
    /// to the center of this node, set the x and y to 0.5
    pub fn drawCircle(this: *Node, center: rl.Vector2, radius: f32, color: rl.Color) void {
        const true_center = center.multiply(this.space.offset);
        this.parent.tools.circle(this.parent, true_center, radius, color);
    }

    pub fn drawText(this: *Node, font: rl.Font, text: [:0]const u8, pos: rl.Vector2, font_size: f32, spacing: f32, tint: rl.Color) void {
        const true_pos = pos.multiply(this.space.offset);
        this.parent.tools.text(this.parent, font, text, true_pos, font_size, spacing, tint);
    }

    // i was in the bathroom thinking about how zig should allow you to back an enum with a bool.
    // i guess a u1 is basically the same, though.
    //
    // i dont really know why i chose to make this an enum instead of just making the functions return a bool to indicate
    // propagation, but oh well.
    pub const Propagation = enum(u1) { propagate, dont_propagate };

    pub const VTable = struct {
        on_click: ?(*const fn (this: *anyopaque, node: *Node, button: rl.MouseButton, relative_pos: rl.Vector2) anyerror!Propagation) = null,
        on_input: ?(*const fn (this: *anyopaque, node: *Node, key: rl.KeyboardKey) anyerror!Propagation) = null,
        draw: ?(*const fn (this: *anyopaque, node: *Node) anyerror!void) = null,
        tick: ?(*const fn (this: *anyopaque, node: *Node, dt: f32) anyerror!void) = null,
        deinit: *const fn (this: *anyopaque) void = nopDeinit,

        pub const nop: VTable = .{};

        fn nopDeinit(_: *anyopaque) void {}
    };

    pub fn onClick(this: *Node, button: rl.MouseButton, relative_pos: rl.Vector2) !void {
        if (this.vtable.on_click != null and try this.vtable.on_click.?(this.self, this, button, relative_pos) != .propagate) return;
        for (this.children.items) |child| {
            const child_rect = rl.Rectangle{
                .x = child.space.offset.x,
                .y = child.space.offset.y,
                .width = child.space.size.x,
                .height = child.space.size.y,
            };
            if (rl.checkCollisionPointRec(relative_pos, child_rect)) {
                try child.onClick(button, relative_pos.subtract(child.space.offset));
                return;
            }
        }
    }

    pub fn onInput(this: *Node, key: rl.KeyboardKey) !void {
        if (this.vtable.on_input != null and try this.vtable.on_input.?(this.self, this, key) != .propagate) return;
        for (this.children.items) |child| {
            try child.onInput(key);
        }
    }

    pub fn draw(this: *Node) !void {
        if (this.vtable.draw) |i| try i(this.self, this);
        for (this.children.items) |child| {
            try child.draw();
        }
    }

    pub fn tick(this: *Node, dt: f32) !void {
        if (this.vtable.tick) |i| try i(this.self, this, dt);
        for (this.children.items) |child| {
            try child.tick(dt);
        }
    }
};

pub const RootNode = struct {
    screen_size: rl.Vector2,
    true_size: rl.Vector2,

    pub const tools: Node.DrawTools = .{
        .rect = drawRect,
        .rect_lines = drawRectLines,
        .line = drawLine,
        .circle = drawCircle,
        .text = drawText,
    };

    pub fn drawRect(node: *Node, rect: rl.Rectangle, color: rl.Color) void {
        const this: *RootNode = @ptrCast(@alignCast(node.self));
        const true_rect: rl.Rectangle = .{
            .x = (rect.x / this.screen_size.x) * this.true_size.x,
            .y = (rect.y / this.screen_size.y) * this.true_size.y,
            .width = rect.width,
            .height = rect.height,
        };
        rl.drawRectangleRec(true_rect, color);
    }

    pub fn drawRectLines(node: *Node, rect: rl.Rectangle, thickness: f32, color: rl.Color) void {
        const this: *RootNode = @ptrCast(@alignCast(node.self));
        const true_rect: rl.Rectangle = .{
            .x = (rect.x / this.screen_size.x) * this.true_size.x,
            .y = (rect.y / this.screen_size.y) * this.true_size.y,
            .width = rect.width,
            .height = rect.height,
        };
        rl.drawRectangleLinesEx(true_rect, thickness, color);
    }

    pub fn drawLine(node: *Node, start: rl.Vector2, end: rl.Vector2, thickness: f32, color: rl.Color) void {
        const this: *RootNode = @ptrCast(@alignCast(node.self));
        const true_start: rl.Vector2 = .{
            .x = (start.x / this.screen_size.x) * this.true_size.x,
            .y = (start.y / this.screen_size.y) * this.true_size.y,
        };
        const true_end: rl.Vector2 = .{
            .x = (end.x / this.screen_size.x) * this.true_size.x,
            .y = (end.y / this.screen_size.y) * this.true_size.y,
        };
        rl.drawLineEx(true_start, true_end, thickness, color);
    }

    pub fn drawCircle(node: *Node, center: rl.Vector2, radius: f32, color: rl.Color) void {
        const this: *RootNode = @ptrCast(@alignCast(node.self));
        const true_center: rl.Vector2 = .{
            .x = (center.x / this.screen_size.x) * this.true_size.x,
            .y = (center.y / this.screen_size.y) * this.true_size.y,
        };
        rl.drawCircleV(true_center, radius, color);
    }

    pub fn drawText(node: *Node, font: rl.Font, text: [:0]const u8, pos: rl.Vector2, font_size: f32, spacing: f32, tint: rl.Color) void {
        const this: *RootNode = @ptrCast(@alignCast(node.self));
        const true_pos: rl.Vector2 = .{
            .x = (pos.x / this.screen_size.x) * this.true_size.x,
            .y = (pos.y / this.screen_size.y) * this.true_size.y,
        };
        rl.drawTextEx(font, text, true_pos, font_size, spacing, tint);
    }

    pub fn toNode(this: *RootNode, gpa: std.mem.Allocator) !*Node {
        const node = try Node.init(gpa, this, .initSize(this.screen_size.x, this.screen_size.y), &.nop);
        node.tools = &tools;
        return node;
    }
};

pub const TextNode = struct {
    gpa: std.mem.Allocator,
    text: [:0]const u8,
    font_size: f32,
    font: rl.Font,
    tint: rl.Color,
    ref_count: usize,

    pub fn initDefault(gpa: std.mem.Allocator, text: [:0]const u8, font_size: f32, tint: rl.Color) !*TextNode {
        const node = try gpa.create(TextNode);
        node.gpa = gpa;
        node.text = try gpa.dupeZ(u8, text);
        node.font_size = font_size;
        node.font = try rl.getFontDefault();
        node.tint = tint;
        return node;
    }

    pub fn deinit(this: *TextNode) void {
        this.gpa.free(this.text);
        this.gpa.destroy(this);
    }

    fn opaqueDeinit(this: *anyopaque) void {
        deinit(@ptrCast(@alignCast(this)));
    }

    pub const vtable: Node.VTable = .{
        .draw = draw,
        .deinit = opaqueDeinit,
        .on_input = null,
        .on_click = null,
    };
    pub fn toNode(this: *TextNode) !*Node {
        return try .init(this.gpa, this, .initSize(0, 0), &vtable);
    }

    fn draw(ptr: *anyopaque, node: *Node) !void {
        const this: *TextNode = @ptrCast(@alignCast(ptr));
        node.drawText(this.font, this.text, .init(0, 0), this.font_size, @floatFromInt(this.font.glyphPadding), this.tint);
    }
};

pub const EmptyNode = struct {
    space: Node.Space,

    pub fn toNode(this: *EmptyNode, gpa: std.mem.Allocator) !*Node {
        return try Node.init(gpa, this, this.space, &.nop);
    }
};
