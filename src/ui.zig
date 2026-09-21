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
    parent: ?*Node,
    gpa: std.mem.Allocator,
    id: ?[:0]const u8,

    pub fn init(gpa: std.mem.Allocator, manager: *anyopaque, space: Space, vtable: *const VTable) !*Node {
        var node = try gpa.create(Node);
        node.manager = manager;
        node.frozen = false;
        node.vtable = vtable;
        node.tools = &.default;
        node.space = space;
        node.children = .empty;
        node.gpa = gpa;
        node.parent = null;
        node.id = null;
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
        if (this.id) |id| this.gpa.free(id);
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

    pub fn addChildAt(this: *Node, child: *Node, offset: rl.Vector2) !void {
        child.space.offset = offset;
        try this.addChild(child);
    }

    /// Removes and deinitializes the child at index `i` and moves all children of a higher index down to fill
    /// the spot.
    pub fn removeChild(this: *Node, i: usize) void {
        const child = this.children.orderedRemove(i);
        child.deinit();
    }

    /// Removes and deinitializes the first child found with id `id`. Moves all children of a higher index down
    /// to fill the spot.
    /// Returns `true` when a child is removed.
    pub fn removeChildId(this: *Node, id: [:0]const u8) bool {
        for (this.children.items, 0..) |child, i| {
            if (child.id == null) continue;
            if (std.mem.eql(u8, child.id.?, id)) {
                this.removeChild(i);
                return true;
            }
        }
        return false;
    }

    /// Sets this node's id. Dupes `id` into ram.
    pub fn setId(this: *Node, id: [:0]const u8) !void {
        this.id = try this.gpa.dupeZ(u8, id);
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
        texture: *const fn (node: *Node, texture: rl.Texture, pos: rl.Vector2, scale: f32, tint: rl.Color) void,
        scale_size: *const fn (node: *Node, size: rl.Vector2) rl.Vector2,
        begin_scissor_mode: *const fn (node: *Node, pos: rl.Vector2, size: rl.Vector2) void,

        pub const default: DrawTools = .{
            .rect = bubbleRect,
            .rect_lines = bubbleRectLines,
            .line = bubbleLine,
            .circle = bubbleCircle,
            .text = bubbleText,
            .measure_text = bubbleMeasureText,
            .texture = bubbleTexture,
            .scale_size = bubbleScaleSize,
            .begin_scissor_mode = bubbleScissorMode,
        };

        // Bubble versions of the node draw functions draw to the absolute space of this node. These do NOT deal with node-space.
        //
        // For example, if the node has a size `.{ .x = 128, .y = 64 }`, the center would be `.{ .x = 64, .y = 32 }`.

        fn bubbleScissorMode(this: *Node, pos: rl.Vector2, size: rl.Vector2) void {
            return this.parent.?.tools.begin_scissor_mode(this.parent.?, pos.add(this.space.offset), size);
        }

        fn bubbleScaleSize(this: *Node, size: rl.Vector2) rl.Vector2 {
            return this.parent.?.tools.scale_size(this.parent.?, size);
        }

        fn bubbleTexture(this: *Node, texture: rl.Texture, pos: rl.Vector2, scale: f32, tint: rl.Color) void {
            const true_pos = pos.add(this.space.offset);
            this.parent.?.tools.texture(this.parent.?, texture, true_pos, scale, tint);
        }

        fn bubbleMeasureText(this: *Node, font: rl.Font, text: [:0]const u8, font_size: f32, spacing: f32) rl.Vector2 {
            return this.parent.?.tools.measure_text(this.parent.?, font, text, font_size, spacing);
        }

        fn bubbleText(this: *Node, font: rl.Font, text: [:0]const u8, pos: rl.Vector2, font_size: f32, spacing: f32, tint: rl.Color) void {
            const true_pos = pos.add(this.space.offset);
            this.parent.?.tools.text(this.parent.?, font, text, true_pos, font_size, spacing, tint);
        }

        fn bubbleRect(this: *Node, rect: rl.Rectangle, color: rl.Color) void {
            const true_rect: rl.Rectangle = .{
                .x = rect.x + this.space.offset.x,
                .y = rect.y + this.space.offset.y,
                .width = rect.width,
                .height = rect.height,
            };
            this.parent.?.tools.rect(this.parent.?, true_rect, color);
        }

        fn bubbleRectLines(this: *Node, rect: rl.Rectangle, thickness: f32, color: rl.Color) void {
            const true_rect: rl.Rectangle = .{
                .x = rect.x + this.space.offset.x,
                .y = rect.y + this.space.offset.y,
                .width = rect.width,
                .height = rect.height,
            };
            this.parent.?.tools.rect_lines(this.parent.?, true_rect, thickness, color);
        }

        fn bubbleLine(this: *Node, start: rl.Vector2, end: rl.Vector2, thickness: f32, color: rl.Color) void {
            const true_start = start.add(this.space.offset);
            const true_end = end.add(this.space.offset);
            this.parent.?.tools.line(this.parent.?, true_start, true_end, thickness, color);
        }

        fn bubbleCircle(this: *Node, center: rl.Vector2, radius: f32, color: rl.Color) void {
            const true_center = center.add(this.space.offset);
            this.parent.?.tools.circle(this.parent.?, true_center, radius, color);
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
        if (this.parent) |p| {
            p.tools.rect(p, true_rect, color);
        } else this.tools.rect(this, true_rect, color);
    }

    /// Draws a rectangle outline in the space of this node
    ///
    /// `rect` values should be expressed as a fraction of that value of this node. For example, to draw
    /// to the center of this node, set the x and y to 0.5
    pub fn drawRectLines(this: *Node, rect: rl.Rectangle, thickness: f32, color: rl.Color) void {
        const true_rect: rl.Rectangle = .{
            .x = (rect.x * this.space.size.x) + this.space.offset.x,
            .y = (rect.y * this.space.size.y) + this.space.offset.y,
            .width = rect.width * this.space.size.x,
            .height = rect.height * this.space.size.y,
        };
        if (this.parent) |p| {
            p.tools.rect_lines(p, true_rect, thickness, color);
        } else this.tools.rect_lines(this, true_rect, thickness, color);
    }

    /// Draws a line in the space of this node
    ///
    /// `start` and `end` values should be expressed as a fraction of that value of this node. For example, to draw
    /// to the center of this node, set the x and y to 0.5
    pub fn drawLine(this: *Node, start: rl.Vector2, end: rl.Vector2, thickness: f32, color: rl.Color) void {
        const true_start = start.multiply(this.space.size).add(this.space.offset);
        const true_end = end.multiply(this.space.size).add(this.space.offset);
        if (this.parent) |p| {
            p.tools.line(p, true_start, true_end, thickness, color);
        } else this.tools.line(this, true_start, true_end, thickness, color);
    }

    /// Draws a circle in the space of this node
    ///
    /// `center` values should be expressed as a fraction of that value of this node. For example, to draw
    /// to the center of this node, set the x and y to 0.5
    pub fn drawCircle(this: *Node, center: rl.Vector2, radius: f32, color: rl.Color) void {
        const true_center = center.multiply(this.space.size).add(this.space.offset);
        if (this.parent) |p| {
            p.tools.circle(p, true_center, radius, color);
        } else this.tools.circle(this, true_center, radius, color);
    }

    /// Draws a circle in the space of this node
    ///
    /// `pos` values should be expressed as a fraction of that value of this node. For example, to draw
    /// to the center of this node, set the x and y to 0.5
    pub fn drawText(this: *Node, font: rl.Font, text: [:0]const u8, pos: rl.Vector2, font_size: f32, spacing: f32, tint: rl.Color) void {
        const true_pos = pos.multiply(this.space.size).add(this.space.offset);
        if (this.parent) |p| {
            p.tools.text(p, font, text, true_pos, font_size, spacing, tint);
        } else this.tools.text(this, font, text, true_pos, font_size, spacing, tint);
    }

    /// Draws a texture in the space of this node
    ///
    /// `pos` values should be expressed as a fraction of that value of this node. For example, to draw
    /// to the center of this node, set the x and y to 0.5
    pub fn drawTexture(this: *Node, texture: rl.Texture, pos: rl.Vector2, scale: f32, tint: rl.Color) void {
        const true_pos = pos.multiply(this.space.size).add(this.space.offset);
        if (this.parent) |p| {
            p.tools.texture(p, texture, true_pos, scale, tint);
        } else this.tools.texture(this, texture, true_pos, scale, tint);
    }

    /// Measures the size of text. Bubbles up until it finds an implementation of `DrawTools.measure_text`, generally
    /// a `RootNode`, returning the size of the text in terms of the `RootNode`'s scale-space.
    pub fn measureText(this: *Node, font: rl.Font, text: [:0]const u8, font_size: f32, spacing: f32) rl.Vector2 {
        if (this.parent) |parent| {
            return parent.tools.measure_text(parent, font, text, font_size, spacing);
        }
        return this.tools.measure_text(this, font, text, font_size, spacing);
    }

    /// Scales the provided size to that of the scale-space.
    pub fn scaleSize(this: *Node, size: rl.Vector2) rl.Vector2 {
        return this.parent.?.tools.scale_size(this.parent.?, size);
    }

    pub fn beginScissorMode(this: *Node, pos: rl.Vector2, size: rl.Vector2) void {
        const true_pos = pos.multiply(this.space.size).add(this.space.offset);
        const true_size = size.multiply(this.space.size);
        if (this.parent) |p| {
            p.tools.begin_scissor_mode(p, true_pos, true_size);
        } else this.tools.begin_scissor_mode(this, true_pos, true_size);
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

    pub fn recalculateNodeGraphSize(this: *Node) !void {
        if (this.parent == null) {
            try this.calculateSize();
        } else {
            try this.parent.?.recalculateNodeGraphSize();
        }
    }

    pub fn move(this: *Node, move_vec: rl.Vector2) !void {
        if (move_vec.equals(.zero())) return;
        this.space.offset = this.space.offset.add(move_vec);
        try this.recalculateNodeGraphSize();
    }

    pub fn setOffset(this: *Node, pos: rl.Vector2) !void {
        if (pos.equals(this.space.offset)) return;
        this.space.offset = pos;
        try this.recalculateNodeGraphSize();
    }

    pub fn resize(this: *Node, size_vec: rl.Vector2) !void {
        if (size_vec.equals(this.space.size)) return;
        this.space.size = size_vec;
        try this.recalculateNodeGraphSize();
    }

    pub fn addSize(this: *Node, addition: rl.Vector2) !void {
        if (addition.equals(.zero())) return;
        this.space.size = this.space.size.add(addition);
        try this.recalculateNodeGraphSize();
    }

    // i was in the bathroom thinking about how zig should allow you to back an enum with a bool.
    // i guess a u1 is basically the same, though.
    //
    // i dont really know why i chose to make this an enum instead of just making the functions return a bool to indicate
    // propagation, but oh well..
    // with the addition of consume, we now know.

    /// Whether to propagate the event to children.
    ///
    /// `consume` will stop the event from being fired in any other nodes, not just children.
    pub const Propagation = enum { propagate, dont_propagate, consume };

    pub const VTable = struct {
        /// Fires whenever a mouse button is pressed and the cursor intersects with the node's space.
        /// `relative_pos` -- the position of the mouse cursor, minus the node's absolute offset. Null if
        /// this node was not clicked.
        ///
        /// Returns whether to propagate this event to children.
        on_click: ?(*const fn (this: *anyopaque, node: *Node, button: rl.MouseButton, relative_pos: ?rl.Vector2) anyerror!Propagation) = null,
        /// Fires whenever a keyboard key is pressed.
        ///
        /// Returns whether to propagate this event to children.
        on_input: ?(*const fn (this: *anyopaque, node: *Node, key: rl.KeyboardKey, repeat: bool) anyerror!Propagation) = null,
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
        ///
        /// For an easy implementation, use `Node.VTable.basicOpaqueDeinit`.
        // i dont know why i didnt make this one nullable, but im too lazy to change it now
        //
        deinit: *const fn (this: *anyopaque) void = nopDeinit,
        /// The only required vtable function. This returns various info about the node's manager, which is then used
        /// for the inspector. Result must be deinitialized.
        ///
        /// For an easy implementation, use `Node.VTable.basicTypeInfo`
        type_info: *const fn (this: *anyopaque, node: *Node, gpa: std.mem.Allocator) anyerror!NodeInfo,

        pub const nop: VTable = .{};

        fn nopDeinit(_: *anyopaque) void {}
        const offset_name = "offset";
        const size_name = "size";
        const id_name = "id";
        const null_str = "null";
        pub fn basicTypeInfo(comptime T: type, comptime fields: []const [:0]const u8) *const fn (this: *anyopaque, node: *Node, gpa: std.mem.Allocator) anyerror!NodeInfo {
            return struct {
                const names = fields;
                pub fn typeInfo(ptr: *anyopaque, node: *Node, gpa: std.mem.Allocator) !NodeInfo {
                    const this: *T = @ptrCast(@alignCast(ptr));
                    const props = try gpa.alloc(NodeInfo.Property, fields.len + 3);
                    props[0] = .{ .string = .{ .name = id_name, .ptr = node.id orelse null_str } };
                    props[1] = .{ .vector = .{ .name = offset_name, .ptr = &node.space.offset } };
                    props[2] = .{ .vector = .{ .name = size_name, .ptr = &node.space.size } };
                    inline for (fields, 0..) |field, i| {
                        const info = @typeInfo(@FieldType(T, field));
                        const FieldType = if (info == .optional) info.optional.child else @FieldType(T, field);
                        props[i + props.len - fields.len] = switch (FieldType) {
                            i32 => .{ .int = .{ .name = names[i], .ptr = &@field(this, field) } },
                            usize => .{ .usize = .{ .name = names[i], .ptr = &@field(this, field) } },
                            f32 => .{ .float = .{ .name = names[i], .ptr = &@field(this, field) } },
                            bool => .{ .boolean = .{ .name = names[i], .ptr = &@field(this, field) } },
                            [:0]const u8, [:0]u8 => .{ .string = .{ .name = names[i], .ptr = @field(this, field) } },
                            rl.Vector2 => .{ .vector = .{ .name = names[i], .ptr = &@field(this, field) } },
                            rl.Color => .{ .color = .{ .name = names[i], .ptr = &@field(this, field) } },
                            else => @compileError("Cannot convert field " ++ @typeName(@FieldType(T, field)) ++ " to a property"),
                        };
                    }
                    return .{
                        .name = @typeName(T),
                        .properties = props,
                    };
                }
            }.typeInfo;
        }
        pub fn basicOpaqueDeinit(comptime T: type) *const fn (this: *anyopaque) void {
            return struct {
                pub fn opaqueDeinit(ptr: *anyopaque) void {
                    T.deinit(@as(*T, @ptrCast(@alignCast(ptr))));
                }
            }.opaqueDeinit;
        }
    };

    pub const NodeInfo = struct {
        name: [:0]const u8,
        properties: ?[]const Property = null,

        pub fn deinit(this: NodeInfo, gpa: std.mem.Allocator) void {
            if (this.properties) |p| {
                gpa.free(p);
            }
        }
        fn Info(comptime PtrT: type) type {
            return struct {
                name: [:0]const u8,
                ptr: ?PtrT,
            };
        }
        pub const Property = union(enum) {
            int: Info(*i32),
            usize: Info(*usize),
            float: Info(*f32),
            boolean: Info(*bool),
            string: Info([:0]const u8),
            vector: Info(*rl.Vector2),
            color: Info(*rl.Color),
        };
    };

    /// Returns whether the event has been `consume`d
    pub fn onClick(this: *Node, button: rl.MouseButton, relative_pos: ?rl.Vector2) !bool {
        if (this.frozen) return false;
        if (this.vtable.on_click) |c| {
            const ret = try c(this.manager, this, button, relative_pos);
            if (ret == .consume) return true;
            if (ret == .dont_propagate) return false;
        }
        for (this.children.items) |child| {
            const child_rect = rl.Rectangle{
                .x = child.space.offset.x,
                .y = child.space.offset.y,
                .width = child.space.size.x,
                .height = child.space.size.y,
            };
            if (relative_pos != null and rl.checkCollisionPointRec(relative_pos.?, child_rect)) {
                if (try child.onClick(button, relative_pos.?.subtract(child.space.offset))) return true;
            } else {
                if (try child.onClick(button, null)) return true;
            }
        }
        return false;
    }

    /// Returns whether the event has been `consume`d.
    pub fn onInput(this: *Node, key: rl.KeyboardKey, repeat: bool) !bool {
        if (this.frozen) return false;
        if (this.vtable.on_input) |i| {
            const ret = try i(this.manager, this, key, repeat);
            if (ret == .consume) return true;
            if (ret == .dont_propagate) return false;
        }
        for (this.children.items) |child| {
            if (try child.onInput(key, repeat)) return true;
        }
        return false;
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

    const tools: Node.DrawTools = .{
        .rect = drawRect,
        .rect_lines = drawRectLines,
        .line = drawLine,
        .circle = drawCircle,
        .text = drawText,
        .measure_text = measureText,
        .scale_size = scaleSize,
        .texture = drawTexture,
        .begin_scissor_mode = beginScissorMode,
    };
    const vtable: Node.VTable = .{
        .add_child = addChild,
        .type_info = Node.VTable.basicTypeInfo(RootNode, &.{ "screen_size", "true_size" }),
    };

    fn drawRect(node: *Node, rect: rl.Rectangle, color: rl.Color) void {
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
        const true_rect: rl.Rectangle = .{
            .x = (rect.x / this.screen_size.x) * this.true_size.x,
            .y = (rect.y / this.screen_size.y) * this.true_size.y,
            .width = (rect.width / this.screen_size.x) * this.true_size.x,
            .height = (rect.height / this.screen_size.y) * this.true_size.y,
        };
        rl.drawRectangleRec(true_rect, color);
    }

    fn drawRectLines(node: *Node, rect: rl.Rectangle, thickness: f32, color: rl.Color) void {
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
        const true_rect: rl.Rectangle = .{
            .x = (rect.x / this.screen_size.x) * this.true_size.x,
            .y = (rect.y / this.screen_size.y) * this.true_size.y,
            .width = (rect.width / this.screen_size.x) * this.true_size.x,
            .height = (rect.height / this.screen_size.y) * this.true_size.y,
        };
        rl.drawRectangleLinesEx(true_rect, thickness, color);
    }

    fn drawLine(node: *Node, start: rl.Vector2, end: rl.Vector2, thickness: f32, color: rl.Color) void {
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

    fn drawCircle(node: *Node, center: rl.Vector2, radius: f32, color: rl.Color) void {
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
        const true_center: rl.Vector2 = .{
            .x = (center.x / this.screen_size.x) * this.true_size.x,
            .y = (center.y / this.screen_size.y) * this.true_size.y,
        };
        rl.drawCircleV(true_center, radius, color);
    }

    fn drawText(node: *Node, font: rl.Font, text: [:0]const u8, pos: rl.Vector2, font_size: f32, spacing: f32, tint: rl.Color) void {
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
        const true_pos: rl.Vector2 = .{
            .x = (pos.x / this.screen_size.x) * this.true_size.x,
            .y = (pos.y / this.screen_size.y) * this.true_size.y,
        };
        rl.drawTextEx(font, text, true_pos, font_size, spacing, tint);
    }

    fn drawTexture(node: *Node, texture: rl.Texture, pos: rl.Vector2, scale: f32, tint: rl.Color) void {
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
        const true_pos = pos.divide(this.screen_size).multiply(this.true_size);
        texture.drawEx(true_pos, 0, scale, tint);
    }

    fn measureText(node: *Node, font: rl.Font, text: [:0]const u8, font_size: f32, spacing: f32) rl.Vector2 {
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
        const vec = rl.measureTextEx(font, text, font_size, spacing);
        return vec.divide(this.true_size).multiply(this.screen_size);
    }

    fn scaleSize(node: *Node, size: rl.Vector2) rl.Vector2 {
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
        return size.divide(this.true_size).multiply(this.screen_size);
    }

    fn beginScissorMode(node: *Node, pos: rl.Vector2, size: rl.Vector2) void {
        const this: *RootNode = @ptrCast(@alignCast(node.manager));
        const true_pos = pos.divide(this.screen_size).multiply(this.true_size);
        const true_size = size.divide(this.screen_size).multiply(this.true_size);
        rl.beginScissorMode(@trunc(true_pos.x), @trunc(true_pos.y), @trunc(true_size.x), @trunc(true_size.y));
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

    pub const vtable: Node.VTable = .{
        .draw = draw,
        .deinit = Node.VTable.basicOpaqueDeinit(TextNode),
        .calculate_size = calculateSize,
        .type_info = Node.VTable.basicTypeInfo(TextNode, &.{ "text", "font_size", "tint" }),
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
        .deinit = Node.VTable.basicOpaqueDeinit(LayoutNode),
        .calculate_size = calculateSize,
        .type_info = Node.VTable.basicTypeInfo(LayoutNode, &.{"gap"}),
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

/// Draws an `Image` to the screen. The `Image` is owned by this node, and will be cleaned up when this node is
/// deinitialized.
/// **Children should not be added to this node, as they will not be accounted for in any calculations.**
pub const ImageNode = struct {
    gpa: std.mem.Allocator,
    image: rl.Image,
    texture: rl.Texture,
    target_size: ?rl.Vector2,
    loaded: bool,

    pub fn init(gpa: std.mem.Allocator, file_name: [:0]const u8, size: ?rl.Vector2) !*ImageNode {
        const node = try gpa.create(ImageNode);
        node.gpa = gpa;
        node.image = try .init(file_name);
        node.target_size = size;
        node.loaded = false;
        return node;
    }

    pub fn initImage(gpa: std.mem.Allocator, image: rl.Image, size: ?rl.Vector2) !*ImageNode {
        const node = try gpa.create(ImageNode);
        node.gpa = gpa;
        node.image = image;
        node.target_size = size;
        node.loaded = false;
        return node;
    }

    pub fn deinit(this: *ImageNode) void {
        if (this.loaded) {
            this.texture.unload();
        }
        this.image.unload();
        this.gpa.destroy(this);
    }

    pub fn resize(this: *ImageNode, size: rl.Vector2) !void {
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
        .deinit = Node.VTable.basicOpaqueDeinit(ImageNode),
        .draw = draw,
        .calculate_size = calculateSize,
        .type_info = Node.VTable.basicTypeInfo(ImageNode, &.{ "loaded", "target_size" }),
    };
    pub fn toNode(this: *ImageNode) !*Node {
        return try Node.init(this.gpa, this, .zero, &vtable);
    }

    fn draw(ptr: *anyopaque, node: *Node) !void {
        const this: *ImageNode = @ptrCast(@alignCast(ptr));
        node.drawTexture(this.texture, .init(0, 0), .white);
    }

    fn calculateSize(ptr: *anyopaque, node: *Node) !rl.Vector2 {
        const this: *ImageNode = @ptrCast(@alignCast(ptr));
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
        .type_info = Node.VTable.basicTypeInfo(RectNode, &.{"color"}),
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

pub const TextureNode = struct {
    gpa: std.mem.Allocator,
    texture: rl.Texture,
    scale: f32,
    owns_texture: bool,

    pub fn init(gpa: std.mem.Allocator, texture: rl.Texture, owns_texture: bool) !*TextureNode {
        const node = try gpa.create(TextureNode);
        node.gpa = gpa;
        node.texture = texture;
        node.scale = 1;
        node.owns_texture = owns_texture;
    }

    pub fn deinit(this: *TextureNode) void {
        if (this.owns_texture) {
            this.texture.unload();
        }
        this.gpa.destroy(this);
    }

    const vtable: Node.VTable = .{
        .deinit = Node.VTable.basicOpaqueDeinit(TextureNode),
        .draw = draw,
        .calculate_size = calculateSize,
        .type_info = Node.VTable.basicTypeInfo(TextureNode, &.{ "scale", "owns_texture" }),
    };
    pub fn toNode(this: *TextureNode) !*Node {
        return try Node.init(this.gpa, this, .zero, &vtable);
    }

    fn draw(ptr: *anyopaque, node: *Node) !void {
        const this: *TextureNode = @ptrCast(@alignCast(ptr));
        node.drawTexture(this.texture, .zero(), this.scale, .white);
    }

    fn calculateSize(ptr: *anyopaque, node: *Node) !rl.Vector2 {
        const this: *TextureNode = @ptrCast(@alignCast(ptr));
        return node.scaleSize(.init(@floatFromInt(this.texture.width), @floatFromInt(this.texture.height)));
    }
};

pub const TextInputNode = struct {
    gpa: std.mem.Allocator,
    text: [:0]u8,
    suggestion: [:0]const u8,
    focused: bool,
    cursor: usize,
    allowed_chars: ?[:0]const u8,
    max_len: usize,

    pub fn init(gpa: std.mem.Allocator, suggestion: ?[:0]const u8, allowed_chars: ?[:0]const u8, buf_size: usize, max_len: usize) !*TextInputNode {
        const node = try gpa.create(TextInputNode);
        node.gpa = gpa;
        // why should I *not* alloc an empty string?
        // dynamic way of creating a usize :O
        node.suggestion = if (suggestion) |s| try gpa.dupeZ(u8, s) else try gpa.allocSentinel(u8, 0, 0);
        node.text = try gpa.allocSentinel(u8, buf_size, 0);
        @memset(node.text, 0);
        node.focused = false;
        node.cursor = 0;
        node.allowed_chars = if (allowed_chars) |a| try gpa.dupeZ(u8, a) else null;
        node.max_len = max_len;
        return node;
    }

    pub fn deinit(this: *TextInputNode) void {
        this.gpa.free(this.text);
        this.gpa.free(this.suggestion);
        if (this.allowed_chars) |a| {
            this.gpa.free(a);
        }
        this.gpa.destroy(this);
    }

    const vtable: Node.VTable = .{
        .deinit = Node.VTable.basicOpaqueDeinit(TextInputNode),
        .type_info = Node.VTable.basicTypeInfo(TextInputNode, &.{ "text", "suggestion", "focused", "allowed_chars", "cursor", "max_len" }),
        .on_click = onClick,
        .on_input = onInput,
        .draw = draw,
        .calculate_size = calculateSize,
    };
    pub fn toNode(this: *TextInputNode) !*Node {
        return try Node.init(this.gpa, this, .zero, &vtable);
    }

    fn calculateSize(_: *anyopaque, node: *Node) !rl.Vector2 {
        return node.space.size;
    }

    fn draw(ptr: *anyopaque, node: *Node) !void {
        const this: *TextInputNode = @ptrCast(@alignCast(ptr));

        node.drawRect(.init(0, 0, 1, 1), if (this.focused) rl.Color.white.brightness(-0.08) else .white);
        node.drawRectLines(.init(0, 0, 1, 1), 3, .dark_gray);
        const scaled = node.scaleSize(.init(5, 0));
        node.beginScissorMode(.init(0, 0), .init(1 - (scaled.x / node.space.size.x), 1));
        const use_suggestion = this.text[0] == 0;
        const txt = if (use_suggestion) this.suggestion else this.text;
        const d = try rl.getFontDefault();
        const cut = try this.gpa.dupeZ(u8, if (use_suggestion) this.suggestion else txt[0..this.cursor]);
        defer this.gpa.free(cut);
        const size = node.measureText(d, cut, 24, 2);
        const char_height = node.measureText(d, "A", 24, 2).y;
        var offset: f32 = 0;
        if (this.focused) {
            if (size.x > node.space.size.x - 40) {
                offset = size.x - (node.space.size.x - 40);
            }
        }
        node.drawText(d, txt, .init((scaled.x - offset) / node.space.size.x, 0.5 - ((char_height / 2) / node.space.size.y)), 24, 2, if (use_suggestion) .light_gray else .black);
        if (this.focused and !use_suggestion) {
            const height: f32 = 0.75;
            node.drawRect(.init((scaled.x + size.x - offset) / node.space.size.x, 0.5 - (height / 2), 2 / node.space.size.x, height), .black);
        }
        rl.endScissorMode();
    }

    fn onClick(ptr: *anyopaque, _: *Node, button: rl.MouseButton, relative_pos: ?rl.Vector2) !Node.Propagation {
        const this: *TextInputNode = @ptrCast(@alignCast(ptr));
        if (button != .left) return .propagate;
        if (relative_pos) |_| {
            this.focused = true;
        } else {
            this.focused = false;
        }

        return .dont_propagate;
    }

    fn onInput(ptr: *anyopaque, _: *Node, key: rl.KeyboardKey, _: bool) !Node.Propagation {
        const this: *TextInputNode = @ptrCast(@alignCast(ptr));
        if (!this.focused) return .propagate;
        switch (key) {
            .escape => {
                this.focused = false;
            },
            .backspace => blk: {
                if (this.cursor == 0) break :blk;
                if (this.cursor == this.text.len) {
                    this.cursor -= 1;
                    this.text[this.cursor] = 0;
                    break :blk;
                }
                this.cursor -= 1;
                @memmove(this.text[this.cursor .. this.text.len - 1], this.text[this.cursor + 1 ..]);
                this.text[this.text.len - 1] = 0;
            },
            .left => {
                if (this.cursor > 0) this.cursor -= 1;
            },
            .right => blk: {
                if (this.cursor < this.text.len) {
                    if (this.text[this.cursor] == 0 and this.text[this.cursor + 1] == 0) break :blk;
                    this.cursor += 1;
                }
            },
            else => blk: {
                if (this.cursor >= this.text.len) break :blk;
                const code = rl.getCharPressed();
                if (code == 0 or !(code >= 32 and code <= 125)) break :blk;
                const char: u8 = @intCast(code);
                if (this.allowed_chars == null or std.mem.findScalar(u8, this.allowed_chars.?, char) != null) {
                    if (this.text[this.cursor] == 0) {
                        this.text[this.cursor] = char;
                        this.cursor += 1;
                        if (this.cursor >= this.text.len and this.text.len < this.max_len) {
                            var new: [:0]u8 = undefined;
                            if (this.text.len + 10 > this.max_len) {
                                new = try this.gpa.allocSentinel(u8, this.max_len, 0);
                            } else {
                                new = try this.gpa.allocSentinel(u8, this.text.len + 10, 0);
                            }
                            @memcpy(new[0..this.text.len], this.text);
                            @memset(new[this.text.len..], 0);
                            this.gpa.free(this.text);
                            this.text = new;
                        }
                    } else {
                        if (this.text[this.text.len - 1] != 0) {
                            if (this.text.len == this.max_len) break :blk;
                            var new: [:0]u8 = undefined;
                            if (this.text.len + 10 > this.max_len) {
                                new = try this.gpa.allocSentinel(u8, this.max_len, 0);
                            } else {
                                new = try this.gpa.allocSentinel(u8, this.text.len + 10, 0);
                            }
                            @memcpy(new[0..this.text.len], this.text);
                            @memset(new[this.text.len..], 0);
                            this.gpa.free(this.text);
                            this.text = new;
                        }
                        @memmove(this.text[this.cursor + 1..], this.text[this.cursor..this.text.len - 1]);
                        this.text[this.cursor] = char;
                        this.cursor += 1;
                    }
                }
            },
        }
        return .consume;
    }
};
