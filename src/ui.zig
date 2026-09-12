const std = @import("std");
const rl = @import("raylib");

/// The building block of all UI.
///
/// All `Node`s derive themselves from a "manager," a struct that manages
/// the data and handles the events passed through a `Node`.
/// Managers are generally allocated in memory, though they don't have to be. If they are, their lifetime
/// is directly tied with the lifetime of the `Node`.
///
/// Each `Node` has children, which are also `Node`s. This creates a UI graph that is traversed to draw,
/// handle input, and more. The UI graph begins with a top-level `Node`, generally a `RootNode`. These
/// `Node`s provide the majority of functionality to its children. They dictate how things are drawn
/// to the screen, how and what events are passed to children, and the lifetime of the entire graph.
/// Once the top-level `Node` is deinitialized, the entire graph is pruned.
///
/// Based loosely on cocos2d-x (from my experience with geometry dash mods. I don't actually know
/// the inner workings of cocos2d-x. I don't even remember if there is a "-" before the "x").
pub const Node = struct {
    manager: *anyopaque,
    frozen: bool,
    vtable: *const VTable,
    tools: *const DrawTools,
    space: Space,
    children: std.ArrayList(*Node),
    parent: *Node,
    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator, manager: *anyopaque, space: Space, vtable: *const VTable) !*Node {
        var node = try gpa.create(Node);
        node.manager = manager;
        node.frozen = false;
        node.vtable = vtable;
        node.tools = &.default;
        node.space = space;
        node.children = .empty;
        node.gpa = gpa;
        return node;
    }

    /// Recursively deinitializes this node and all children in the graph of this node.
    /// Fires the `deinit` event on this node and all children.
    pub fn deinit(this: *Node) void {
        for (this.children.items) |child| {
            child.deinit();
        }
        this.vtable.deinit(this.manager);
        this.children.deinit(this.gpa);
        this.gpa.destroy(this);
    }

    /// Adds `child` to this node's children. Tries to fire the `parented` event on the child and the `add_child`
    /// event on the the parent (this node).
    pub fn addChild(this: *Node, child: *Node) !void {
        try this.children.append(this.gpa, child);
        child.parent = this;
        if (this.vtable.add_child) |i| try i(this.manager, this, child);
        if (child.vtable.parented) |i| try i(child.manager, child, this);
    }

    /// Removes and deinitializes the child at index `i` and moves all children of a higher index down to fill
    /// the spot.
    pub fn removeChild(this: *Node, i: usize) void {
        const child = this.children.orderedRemove(i);
        child.deinit();
    }

    pub const Space = struct {
        offset: rl.Vector2,
        size: rl.Vector2,

        pub const zero: Space = .{ .offset = .{ .x = 0, .y = 0 }, .size = .{ .x = 0, .y = 0 } };
        pub fn initSize(width: f32, height: f32) Space {
            return .{
                .offset = .init(0, 0),
                .size = .init(width, height),
            };
        }
    };

    /// Provides functions for drawing relative to node-space. A top-level `Node`, such as `RootNode`, should
    /// provide its own `DrawTools` and do the actual drawing to the screen.
    ///
    /// Calls to these functions will bubble up to the root node.
    pub const DrawTools = struct {
        rect: *const fn (node: *Node, rect: rl.Rectangle, color: rl.Color) void,
        rect_lines: *const fn (node: *Node, rect: rl.Rectangle, thickness: f32, color: rl.Color) void,
        line: *const fn (node: *Node, start: rl.Vector2, end: rl.Vector2, thickness: f32, color: rl.Color) void,
        circle: *const fn (node: *Node, center: rl.Vector2, radius: f32, color: rl.Color) void,
        text: *const fn (node: *Node, font: rl.Font, text: [:0]const u8, pos: rl.Vector2, font_size: f32, spacing: f32, tint: rl.Color) void,
        measure_text: *const fn (node: *Node, font: rl.Font, text: [:0]const u8, font_size: f32, spacing: f32) rl.Vector2,
        texture: *const fn (node: *Node, texture: rl.Texture, pos: rl.Vector2, tint: rl.Color) void,
        scale_size: *const fn (node: *Node, size: rl.Vector2) rl.Vector2,

        pub const default: DrawTools = .{
            .rect = bubbleRect,
            .rect_lines = bubbleRectLines,
            .line = bubbleLine,
            .circle = bubbleCircle,
            .text = bubbleText,
            .measure_text = bubbleMeasureText,
            .texture = bubbleTexture,
            .scale_size = bubbleScaleSize,
        };

        // Bubble versions of the node draw functions draw to the absolute space of this node.
        //
        // For example, if the node has a size `.{ .x = 128, .y = 64 }`, the center would be `.{ .x = 64, .y = 32 }`.

        fn bubbleScaleSize(this: *Node, size: rl.Vector2) rl.Vector2 {
            return this.parent.tools.scale_size(this.parent, size);
        }

        fn bubbleTexture(this: *Node, texture: rl.Texture, pos: rl.Vector2, tint: rl.Color) void {
            const true_pos = pos.add(this.space.offset);
            this.parent.tools.texture(this.parent, texture, true_pos, tint);
        }

        fn bubbleMeasureText(this: *Node, font: rl.Font, text: [:0]const u8, font_size: f32, spacing: f32) rl.Vector2 {
            return this.parent.tools.measure_text(this.parent, font, text, font_size, spacing);
        }

        fn bubbleText(this: *Node, font: rl.Font, text: [:0]const u8, pos: rl.Vector2, font_size: f32, spacing: f32, tint: rl.Color) void {
            const true_pos = pos.add(this.space.offset);
            this.parent.tools.text(this.parent, font, text, true_pos, font_size, spacing, tint);
        }

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
    /// `rect` values should be expressed as a fraction of that value of this node. For example, to draw
    /// to the center of this node, set the x and y to 0.5
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
    /// `rect` values should be expressed as a fraction of that value of this node. For example, to draw
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
    /// `start` and `end` values should be expressed as a fraction of that value of this node. For example, to draw
    /// to the center of this node, set the x and y to 0.5
    pub fn drawLine(this: *Node, start: rl.Vector2, end: rl.Vector2, thickness: f32, color: rl.Color) void {
        const true_start = start.multiply(this.space.size).add(this.space.offset);
        const true_end = end.multiply(this.space.size).add(this.space.offset);
        this.parent.tools.line(this.parent, true_start, true_end, thickness, color);
    }

    /// Draws a circle in the space of this node
    ///
    /// `center` values should be expressed as a fraction of that value of this node. For example, to draw
    /// to the center of this node, set the x and y to 0.5
    pub fn drawCircle(this: *Node, center: rl.Vector2, radius: f32, color: rl.Color) void {
        const true_center = center.multiply(this.space.size).add(this.space.offset);
        this.parent.tools.circle(this.parent, true_center, radius, color);
    }

    /// Draws a circle in the space of this node
    ///
    /// `pos` values should be expressed as a fraction of that value of this node. For example, to draw
    /// to the center of this node, set the x and y to 0.5
    pub fn drawText(this: *Node, font: rl.Font, text: [:0]const u8, pos: rl.Vector2, font_size: f32, spacing: f32, tint: rl.Color) void {
        const true_pos = pos.multiply(this.space.size).add(this.space.offset);
        this.parent.tools.text(this.parent, font, text, true_pos, font_size, spacing, tint);
    }

    /// Draws a texture in the space of this node
    ///
    /// `pos` values should be expressed as a fraction of that value of this node. For example, to draw
    /// to the center of this node, set the x and y to 0.5
    pub fn drawTexture(this: *Node, texture: rl.Texture, pos: rl.Vector2, tint: rl.Color) void {
        const true_pos = pos.multiply(this.space.size).add(this.space.offset);
        this.parent.tools.texture(this.parent, texture, true_pos, tint);
    }

    /// Measures the size of text. Bubbles up until it finds an implementation of `DrawTools.measure_text`, generally
    /// a `RootNode`, returning the size of the text in terms of the `RootNode`'s scale-space.
    pub fn measureText(this: *Node, font: rl.Font, text: [:0]const u8, font_size: f32, spacing: f32) rl.Vector2 {
        return this.parent.tools.measure_text(this.parent, font, text, font_size, spacing);
    }

    /// Scales the provided size to that of the scale-space.
    pub fn scaleSize(this: *Node, size: rl.Vector2) rl.Vector2 {
        return this.parent.tools.scale_size(this.parent, size);
    }

    /// Loops through each child, calling `calculateSize`, adding the result to this node's calculated size.
    ///
    /// If this node's `vtable` contains a `calculate_size` member, it calls that instead.
    pub fn calculateSize(this: *Node) !void {
        if (this.vtable.calculate_size) |i| {
            this.space.size = try i(this.manager, this);
        } else {
            var size: rl.Vector2 = .init(0, 0);
            var largest_offset: rl.Vector2 = .init(0, 0);
            for (this.children.items) |child| {
                try child.calculateSize();
                size = size.add(child.space.size);
                if (child.space.offset.x > largest_offset.x) largest_offset.x = child.space.offset.x;
                if (child.space.offset.y > largest_offset.y) largest_offset.y = child.space.offset.y;
            }
            this.space.size = size.add(largest_offset);
        }
    }

    // i was in the bathroom thinking about how zig should allow you to back an enum with a bool.
    // i guess a u1 is basically the same, though.
    //
    // i dont really know why i chose to make this an enum instead of just making the functions return a bool to indicate
    // propagation, but oh well..
    pub const Propagation = enum(u1) { propagate, dont_propagate };

    pub const VTable = struct {
        /// Fires whenever a mouse button is pressed and the cursor intersects with the node's space.
        /// `relative_pos` -- the position of the mouse cursor, minus the node's absolute offset.
        ///
        /// Returns whether to propagate this event to children.
        on_click: ?(*const fn (this: *anyopaque, node: *Node, button: rl.MouseButton, relative_pos: rl.Vector2) anyerror!Propagation) = null,
        /// Fires whenever a keyboard key is pressed.
        ///
        /// Returns whether to propagate this event to children.
        on_input: ?(*const fn (this: *anyopaque, node: *Node, key: rl.KeyboardKey) anyerror!Propagation) = null,
        /// Fires whenever a child is added to this node, before `parented` is fired on the child.
        add_child: ?(*const fn (this: *anyopaque, node: *Node, child: *Node) anyerror!void) = null,
        /// Fires every frame, allowing a node to draw to the screen using the draw functions available through
        /// `node`.
        draw: ?(*const fn (this: *anyopaque, node: *Node) anyerror!void) = null,
        /// Fires before every frame.
        tick: ?(*const fn (this: *anyopaque, node: *Node, dt: f32) anyerror!void) = null,
        /// Fires when this node becomes a child of another node, after `add_child` is fired on the parent.
        parented: ?(*const fn (this: *anyopaque, node: *Node, parent: *Node) anyerror!void) = null,
        /// Returns the size of this node. This is automatically called recursively on the node graph when
        /// this node or a parent node is attached to a `RootNode`.
        ///
        /// If this member has a value, the function pointed to must call `calculateSize` on each of its children.
        calculate_size: ?(*const fn (this: *anyopaque, node: *Node) anyerror!rl.Vector2) = null,
        /// Fires when the node is removed from its graph, causing it, and all of its children, to be deinitialized.
        /// Allows automatic cleanup of a custom node's resources.
        ///
        /// Any node that allocates memory or requires any other cleanup after use should provide a `deinit` function.
        // i dont know why i didnt make this one nullable, but im too lazy to change it now
        deinit: *const fn (this: *anyopaque) void = nopDeinit,

        pub const nop: VTable = .{};

        fn nopDeinit(_: *anyopaque) void {}
        pub fn basicOpaqueDeinit(comptime T: type) *const fn (this: *anyopaque) void {
            return struct {
                pub fn opaqueDeinit(ptr: *anyopaque) void {
                    T.deinit(@as(*T, @ptrCast(@alignCast(ptr))));
                }
            }.opaqueDeinit;
        }
    };

    pub fn onClick(this: *Node, button: rl.MouseButton, relative_pos: rl.Vector2) !void {
        if (this.frozen) return;
        if (this.vtable.on_click != null and try this.vtable.on_click.?(this.manager, this, button, relative_pos) != .propagate) return;
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
        if (this.frozen) return;
        if (this.vtable.on_input != null and try this.vtable.on_input.?(this.manager, this, key) != .propagate) return;
        for (this.children.items) |child| {
            try child.onInput(key);
        }
    }

    pub fn draw(this: *Node) !void {
        if (this.vtable.draw) |i| try i(this.manager, this);
        for (this.children.items) |child| {
            try child.draw();
        }
    }

    pub fn tick(this: *Node, dt: f32) !void {
        if (this.vtable.tick) |i| try i(this.manager, this, dt);
        for (this.children.items) |child| {
            try child.tick(dt);
        }
    }
};

/// The general-purpose top-level node. Allows the user to specify a custom screen size that will be scaled to fit
/// the actual screen size. It also provides all `DrawTools` functions to draw to the screen.
///
/// Whenever a node is added as a child to a `RootNode`, it calculates the size of the new child node.
pub const RootNode = struct {
    screen_size: rl.Vector2,
    true_size: rl.Vector2,

    pub const tools: Node.DrawTools = .{
        .rect = drawRect,
        .rect_lines = drawRectLines,
        .line = drawLine,
        .circle = drawCircle,
        .text = drawText,
        .measure_text = measureText,
        .scale_size = scaleSize,
        .texture = drawTexture,
    };
    pub const vtable: Node.VTable = .{
        .add_child = addChild,
    };

    pub fn drawRect(node: *Node, rect: rl.Rectangle, color: rl.Color) void {
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
        const true_rect: rl.Rectangle = .{
            .x = (rect.x / this.screen_size.x) * this.true_size.x,
            .y = (rect.y / this.screen_size.y) * this.true_size.y,
            .width = rect.width,
            .height = rect.height,
        };
        rl.drawRectangleRec(true_rect, color);
    }

    pub fn drawRectLines(node: *Node, rect: rl.Rectangle, thickness: f32, color: rl.Color) void {
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
        const true_rect: rl.Rectangle = .{
            .x = (rect.x / this.screen_size.x) * this.true_size.x,
            .y = (rect.y / this.screen_size.y) * this.true_size.y,
            .width = rect.width,
            .height = rect.height,
        };
        rl.drawRectangleLinesEx(true_rect, thickness, color);
    }

    pub fn drawLine(node: *Node, start: rl.Vector2, end: rl.Vector2, thickness: f32, color: rl.Color) void {
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
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
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
        const true_center: rl.Vector2 = .{
            .x = (center.x / this.screen_size.x) * this.true_size.x,
            .y = (center.y / this.screen_size.y) * this.true_size.y,
        };
        rl.drawCircleV(true_center, radius, color);
    }

    pub fn drawText(node: *Node, font: rl.Font, text: [:0]const u8, pos: rl.Vector2, font_size: f32, spacing: f32, tint: rl.Color) void {
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
        const true_pos: rl.Vector2 = .{
            .x = (pos.x / this.screen_size.x) * this.true_size.x,
            .y = (pos.y / this.screen_size.y) * this.true_size.y,
        };
        rl.drawTextEx(font, text, true_pos, font_size, spacing, tint);
    }

    pub fn drawTexture(node: *Node, texture: rl.Texture, pos: rl.Vector2, tint: rl.Color) void {
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
        const true_pos = pos.divide(this.screen_size).multiply(this.true_size);
        texture.drawV(true_pos, tint);
    }

    pub fn measureText(node: *Node, font: rl.Font, text: [:0]const u8, font_size: f32, spacing: f32) rl.Vector2 {
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
        const vec = rl.measureTextEx(font, text, font_size, spacing);
        return vec.divide(this.true_size).multiply(this.screen_size);
    }

    pub fn scaleSize(node: *Node, size: rl.Vector2) rl.Vector2 {
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
        return size.divide(this.true_size).multiply(this.screen_size);
    }

    fn addChild(_: *anyopaque, node: *Node, _: *Node) !void {
        try node.calculateSize();
    }

    pub fn toNode(this: *RootNode, gpa: std.mem.Allocator) !*Node {
        const node = try Node.init(gpa, this, .initSize(this.screen_size.x, this.screen_size.y), &vtable);
        node.tools = &tools;
        return node;
    }
};

/// A node that draw text to the screen.
pub const TextNode = struct {
    gpa: std.mem.Allocator,
    text: [:0]const u8,
    font_size: f32,
    font: rl.Font,
    tint: rl.Color,

    /// Dupes `text` into ram
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
        .calculate_size = calculateSize,
    };
    pub fn toNode(this: *TextNode) !*Node {
        return try Node.init(this.gpa, this, .initSize(0, 0), &vtable);
    }

    fn draw(ptr: *anyopaque, node: *Node) !void {
        const this: *TextNode = @ptrCast(@alignCast(ptr));
        node.drawText(this.font, this.text, .init(0, 0), this.font_size, @floatFromInt(this.font.glyphPadding), this.tint);
    }

    fn calculateSize(ptr: *anyopaque, node: *Node) !rl.Vector2 {
        const this: *TextNode = @ptrCast(@alignCast(ptr));
        return node.measureText(this.font, this.text, this.font_size, @floatFromInt(this.font.glyphPadding));
    }
};

/// An empty node. No different than just initializing a `Node` on its own.
pub const EmptyNode = struct {
    space: Node.Space,

    pub fn toNode(this: *EmptyNode, gpa: std.mem.Allocator) !*Node {
        return try Node.init(gpa, this, this.space, &.nop);
    }
};

/// A node that automatically lays out its children to follow a simple scheme.
pub const LayoutNode = struct {
    gap: f32,
    direction: Direction,
    flow: Flow,
    gpa: std.mem.Allocator,

    const vtable: Node.VTable = .{
        .deinit = opaqueDeinit,
        .calculate_size = calculateSize,
    };

    pub fn init(gpa: std.mem.Allocator, gap: f32, direction: Direction, flow: Flow) !*LayoutNode {
        const node = try gpa.create(LayoutNode);
        node.gap = gap;
        node.direction = direction;
        node.flow = flow;
        node.gpa = gpa;
        return node;
    }

    pub fn deinit(this: *LayoutNode) void {
        this.gpa.destroy(this);
    }

    fn opaqueDeinit(ptr: *anyopaque) void {
        deinit(@ptrCast(@alignCast(ptr)));
    }

    pub fn toNode(this: *LayoutNode) !*Node {
        return try Node.init(this.gpa, this, .initSize(0, 0), &vtable);
    }

    pub const Direction = enum {
        horizontal,
        vertical,
    };

    pub const Flow = enum {
        /// Horizontal: left. Vertical: top.
        ///
        /// Requires one loop through node children
        start,
        /// Horizontal: right. Vertical: bottom.
        ///
        /// Requires two loops through node children
        end,
    };

    fn calculateSize(ptr: *anyopaque, node: *Node) !rl.Vector2 {
        const this: *LayoutNode = @ptrCast(@alignCast(ptr));
        return switch (this.direction) {
            .horizontal => try this.horizLayout(node),
            .vertical => try this.vertLayout(node),
        };
    }

    fn horizLayout(this: *LayoutNode, node: *Node) !rl.Vector2 {
        switch (this.flow) {
            .start => {
                var off: f32 = 0;
                var height: f32 = 0;
                for (node.children.items) |child| {
                    try child.calculateSize();
                    child.space.offset.x = off;
                    off += child.space.size.x + this.gap;
                    if (child.space.size.y > height) height = child.space.size.y;
                }
                if (off != 0) off -= this.gap;
                return .{ .x = off, .y = height };
            },
            .end => {
                var width: f32 = 0;
                for (node.children.items) |child| {
                    try child.calculateSize();
                    width += child.space.size.x + this.gap;
                }
                if (width != 0) width -= this.gap;
                var off: f32 = width;
                var height: f32 = 0;
                for (node.children.items) |child| {
                    child.space.offset.x = off;
                    off -= child.space.size.x + this.gap;
                    if (child.space.size.y > height) height = child.space.size.y;
                }
                return .{ .x = width, .y = height };
            },
        }
    }

    fn vertLayout(this: *LayoutNode, node: *Node) !rl.Vector2 {
        switch (this.flow) {
            .start => {
                var off: f32 = 0;
                var height: f32 = 0;
                for (node.children.items) |child| {
                    try child.calculateSize();
                    child.space.offset.y = off;
                    off += child.space.size.y + this.gap;
                    if (child.space.size.x > height) height = child.space.size.x;
                }
                if (off != 0) off -= this.gap;
                return .{ .x = height, .y = off };
            },
            .end => {
                var width: f32 = 0;
                for (node.children.items) |child| {
                    try child.calculateSize();
                    width += child.space.size.y + this.gap;
                }
                if (width != 0) width -= this.gap;
                var off: f32 = width;
                var height: f32 = 0;
                for (node.children.items) |child| {
                    child.space.offset.y = off;
                    off -= child.space.size.y + this.gap;
                    if (child.space.size.x > height) height = child.space.size.x;
                }
                return .{ .y = width, .x = height };
            },
        }
    }
};

/// Draws a `Texture` to the screen. The `Texture` is owned by this node, and will be cleaned up when this node is
/// deinitialized.
/// **Children should not be added to this node, as they will not be accounted for in any calculations.**
pub const TextureNode = struct {
    gpa: std.mem.Allocator,
    image: rl.Image,
    texture: rl.Texture,
    target_size: ?rl.Vector2,
    loaded: bool,

    pub fn init(gpa: std.mem.Allocator, file_name: [:0]const u8, size: ?rl.Vector2) !*TextureNode {
        const node = try gpa.create(TextureNode);
        node.gpa = gpa;
        node.image = try .init(file_name);
        node.target_size = size;
        node.loaded = false;
        return node;
    }

    pub fn initImage(gpa: std.mem.Allocator, image: rl.Image, size: ?rl.Vector2) !*TextureNode {
        const node = try gpa.create(TextureNode);
        node.gpa = gpa;
        node.image = image;
        node.target_size = size;
        node.loaded = false;
        return node;
    }

    pub fn deinit(this: *TextureNode) void {
        if (this.loaded) {
            this.texture.unload();
        }
        this.image.unload();
        this.gpa.destroy(this);
    }

    pub fn resize(this: *TextureNode, size: rl.Vector2) !void {
        this.target_size = size;
        if (this.loaded) {
            this.loaded = false;
            this.texture.unload();
        }
        this.image.resize(@intFromFloat(size.x), @intFromFloat(size.y));
        this.texture = try rl.Texture.fromImage(this.image);
        this.loaded = true;
    }

    const vtable: Node.VTable = .{
        .deinit = Node.VTable.basicOpaqueDeinit(TextureNode),
        .draw = draw,
        .calculate_size = calculateSize,
    };
    pub fn toNode(this: *TextureNode) !*Node {
        return try Node.init(this.gpa, this, .zero, &vtable);
    }

    fn draw(ptr: *anyopaque, node: *Node) !void {
        const this: *TextureNode = @ptrCast(@alignCast(ptr));
        node.drawTexture(this.texture, .init(0, 0), .white);
    }

    fn calculateSize(ptr: *anyopaque, node: *Node) !rl.Vector2 {
        const this: *TextureNode = @ptrCast(@alignCast(ptr));
        if (!this.loaded) {
            if (this.target_size) |size| {
                this.image.resize(@intFromFloat(size.x), @intFromFloat(size.y));
            }
            this.texture = try .fromImage(this.image);
            this.loaded = true;
        }
        return node.scaleSize(.init(@floatFromInt(this.texture.width), @floatFromInt(this.texture.height)));
    }
};

// Draw a rectangle the same size as the node.
pub const RectNode = struct {
    gpa: std.mem.Allocator,
    color: rl.Color,

    const vtable: Node.VTable = .{
        .draw = draw,
        .deinit = Node.VTable.basicOpaqueDeinit(RectNode),
    };

    pub fn init(gpa: std.mem.Allocator, color: rl.Color) !*RectNode {
        const node = try gpa.create(RectNode);
        node.gpa = gpa;
        node.color = color;
        return node;
    }

    pub fn deinit(this: *RectNode) void {
        this.gpa.destroy(this);
    }

    pub fn toNode(this: *RectNode) !*Node {
        return try Node.init(this.gpa, this, .zero, &vtable);
    }

    fn draw(ptr: *anyopaque, node: *Node) !void {
        const this: *RectNode = @ptrCast(@alignCast(ptr));
        node.drawRect(.init(0, 0, 1, 1), this.color);
    }
};
