const std = @import("std");
const rgui = @import("raygui");
const rl = @import("raylib");
const ui = @import("ui.zig");

const Inspector = @This();

gpa: std.mem.Allocator,
width: f32,
height: f32,
texture: rl.RenderTexture,
root_entry: Entry,
is_open: bool = false,
prop_list_view: rl.Rectangle,
prop_list_scroll: rl.Vector2 = .zero(),
func_list_view: rl.Rectangle,
func_list_scroll: rl.Vector2 = .zero(),
node_list_view: rl.Rectangle = .init(0, 0, 0, 0),
node_list_scroll: rl.Vector2 = .zero(),
selected_entry: ?*Entry = null,

pub fn init(gpa: std.mem.Allocator, width: f32, height: f32) !@This() {
    rgui.setStyle(.default, .text_size, 10);
    rgui.setStyle(.button, .text_alignment, @intFromEnum(rgui.TextAlignment.left));
    rgui.setStyle(.button, .text_padding, 4);
    return .{
        .gpa = gpa,
        .width = width,
        .height = height,
        .texture = try .init(@intFromFloat(width), @intFromFloat(height)),
        .root_entry = undefined,
        .prop_list_view = .init(0, height * 2 / 3, width / 2, height / 3),
        .func_list_view = .init(width / 2, height * 2 / 3, width / 2, height / 3),
    };
}

pub fn deinit(this: @This()) void {
    this.texture.unload();
    this.root_entry.deinit();
}

pub fn beginDraw(this: @This()) void {
    this.texture.begin();
}

pub fn endDraw(this: @This()) void {
    this.texture.end();
}

pub fn setRoot(this: *Inspector, node: *ui.Node) !void {
    this.root_entry = try .init(this.gpa, node, this);
}

pub const Entry = struct {
    open: bool = false,
    info: ui.Node.NodeInfo,
    state: ?[]InfoState,
    inspector: *Inspector,
    node: *ui.Node,
    children: []Entry,
    function_state: FunctionState,
    gpa: std.mem.Allocator,

    pub const FunctionState = struct {
        recalculate_err: ?[:0]const u8 = null,
        move_err: ?[:0]const u8 = null,
        move_x: InfoState.FloatState,
        move_y: InfoState.FloatState,
        move_vec: rl.Vector2,

        pub fn init(gpa: std.mem.Allocator, move_vec: rl.Vector2) !FunctionState {
            return .{
                .move_x = .{ .str = try gpa.allocSentinel(u8, 32, 0) },
                .move_y = .{ .str = try gpa.allocSentinel(u8, 32, 0) },
                .move_vec = move_vec,
            };
        }

        pub fn deinit(this: FunctionState, gpa: std.mem.Allocator) void {
            gpa.free(this.move_x.str);
            gpa.free(this.move_y.str);
        }
    };

    pub const InfoState = union(enum) {
        none: void,
        float: FloatState,
        int: struct {
            editing: bool = false,
        },
        vector: struct {
            x: FloatState,
            y: FloatState,
        },

        pub const FloatState = struct {
            // not an array to conserve size
            str: [:0]u8,
            editing: bool = false,
            accessed: bool = false,

            pub fn init(gpa: std.mem.Allocator) !FloatState {
                return .{ .str = try gpa.allocSentinel(u8, 32, 0) };
            }

            pub fn deinit(this: FloatState, gpa: std.mem.Allocator) void {
                gpa.free(this.str);
            }

            pub fn draw(this: *FloatState, offset: rl.Vector2, ptr: *f32, name: [:0]const u8) !void {
                if (!this.accessed) {
                    // holy cursed
                    @memset(this.str, 0);
                    _ = try std.fmt.bufPrintZ(this.str, "{d:0<0.2}", .{ptr.*});
                    this.accessed = true;
                }
                const width: f32 = @floatFromInt(rgui.getTextWidth(name));
                if (rgui.valueBoxFloat(.init(offset.x + width, offset.y, 100, 30), name, this.str, ptr, this.editing) > 0) {
                    this.editing = !this.editing;
                }
            }
        };

        pub fn deinit(this: InfoState, gpa: std.mem.Allocator) void {
            switch (this) {
                .float => |f| {
                    f.deinit(gpa);
                },
                .vector => |v| {
                    v.x.deinit(gpa);
                    v.y.deinit(gpa);
                },
                else => {},
            }
        }

        pub fn floatState(gpa: std.mem.Allocator) !InfoState {
            return .{ .float = try .init(gpa) };
        }

        pub fn vecState(gpa: std.mem.Allocator) !InfoState {
            return .{ .vector = .{ .x = try .init(gpa), .y = try .init(gpa) } };
        }
    };

    pub fn draw(this: *Entry, index: *f32, depth: f32, offset: rl.Vector2) !void {
        const btn_off: f32 = if (this.children.len != 0) 30 else 0;
        if (this.children.len != 0) {
            const icon = if (this.open) rgui.IconName.arrow_down else rgui.IconName.arrow_right;
            if (rgui.button(.init(offset.x + 15 * depth, offset.y + 30 * index.*, 30, 30), rgui.iconText(@intFromEnum(icon), ""))) {
                this.open = !this.open;
            }
        }
        const name = if (this.node.id) |i| try std.mem.concatWithSentinel(this.gpa, u8, &.{ "\"", i, "\" ", this.info.name }, 0) else this.info.name;
        defer if (this.node.id != null) this.gpa.free(name);
        const size: f32 = @floatFromInt(rgui.getTextWidth(name) + (rgui.getStyle(.button, .text_padding) * 2));
        const width = if (size > this.inspector.width) size else (this.inspector.width / 3) - btn_off - (depth * 15);
        if (rgui.button(.init(offset.x + btn_off + (15 * depth), offset.y + 30 * index.*, width, 30), name)) {
            this.inspector.selected_entry = this;
        }
        if (this.open) {
            for (this.children) |*child| {
                index.* += 1;
                try child.draw(index, depth + 1, offset);
            }
        }
    }

    fn drawNullProperty(gpa: std.mem.Allocator, name: [:0]const u8, x: f32, y: f32, height: f32) !void {
        const concat = try std.mem.concatWithSentinel(gpa, u8, &.{ name, ": null" }, 0);
        defer gpa.free(concat);
        const width: f32 = @floatFromInt(rgui.getTextWidth(concat) + rgui.getStyle(.button, .text_padding) * 2);
        _ = rgui.label(.init(x, y, width, height), concat);
    }

    pub fn drawProperties(this: *Entry, offset: rl.Vector2) !void {
        this.info.deinit(this.gpa);
        this.info = try this.node.vtable.type_info(this.node.manager, this.node, this.gpa);
        if (this.info.properties) |p| {
            const state = this.state.?;
            var i: f32 = 0;
            for (p, 0..) |prop, idx| {
                defer i += 1;
                switch (prop) {
                    inline else => |r| {
                        if (r.ptr == null) {
                            try drawNullProperty(this.gpa, r.name, 5, 5 + offset.y + i * 35, 30);
                            continue;
                        }
                    },
                }
                switch (prop) {
                    .boolean => |b| {
                        _ = rgui.checkBox(.init(5, 5 + offset.y + i * 35, 30, 30), b.name, b.ptr.?);
                    },
                    .int => |int| {
                        _ = rgui.valueBox(.init(5, 5 + offset.y + i * 35, 100, 30), int.name, int.ptr.?, std.math.minInt(i32), std.math.maxInt(i32), state[idx].int.editing);
                    },
                    .float => |f| {
                        try state[idx].float.draw(offset.add(.init(5, 5 + i * 35)), f.ptr.?, f.name);
                    },
                    .string => |s| {
                        const width: f32 = @floatFromInt(rgui.getTextWidth(s.name) + rgui.getTextWidth(": \"") + rgui.getTextWidth(s.ptr.?) + rgui.getTextWidth("\"") + rgui.getStyle(.button, .text_padding) * 2);
                        const len = std.mem.findSentinel(u8, 0, s.ptr.?);
                        const concat = try std.mem.concatWithSentinel(this.gpa, u8, &.{ s.name, ": \"", s.ptr.?[0..len], "\"" }, 0);
                        defer this.gpa.free(concat);
                        _ = rgui.label(.init(5, 5 + offset.y + i * 35, width, 30), concat);
                    },
                    .vector => |v| {
                        const v_state = &state[idx].vector;
                        const width: f32 = @floatFromInt(rgui.getTextWidth(v.name) + rgui.getTextWidth(": ") + 8);
                        const concat = try std.mem.concatWithSentinel(this.gpa, u8, &.{ v.name, ": " }, 0);
                        defer this.gpa.free(concat);
                        _ = rgui.label(.init(5, 5 + offset.y + i * 35, width, 30), concat);
                        const x_w: f32 = @floatFromInt(rgui.getTextWidth("x"));
                        try v_state.x.draw(offset.add(.init(5 + width, 5 + i * 35)), &v.ptr.?.x, "x");
                        try v_state.y.draw(offset.add(.init(105 + width + x_w * 2, 5 + i * 35)), &v.ptr.?.y, "y");
                    },
                    .color => |c| {
                        const width: f32 = @floatFromInt(rgui.getTextWidth(c.name) + rgui.getTextWidth(": ") + rgui.getStyle(.button, .text_padding) * 2);
                        const concat = try std.mem.concatWithSentinel(this.gpa, u8, &.{ c.name, ": " }, 0);
                        defer this.gpa.free(concat);
                        _ = rgui.label(.init(5, 5 + offset.y + i * 35, width, 30), concat);
                        rl.drawRectangleRec(.init(width + 5, 5 + offset.y + i * 35, 30, 30), c.ptr.?.*);
                        const color = rgui.getStyle(.checkbox, .border_color_normal);
                        rl.drawRectangleLinesEx(.init(width + 5, 5 + offset.y + i * 35, 30, 30), 1, rl.Color.fromInt(@bitCast(color)));
                    },
                }
            }
        }
    }

    pub fn drawFunctions(this: *Entry, offset: rl.Vector2, gap: f32) !void {
        _ = gap;
        if (button(offset, 30, "Recalculate Node Graph")) {
            this.node.recalculateNodeGraphSize() catch |err| std.log.err("error recalc {any}", .{err});
        }
    }

    fn button(pos: rl.Vector2, height: f32, text: [:0]const u8) bool {
        const width: f32 = @floatFromInt(rgui.getTextWidth(text) + rgui.getStyle(.button, .text_padding) * 3);
        return rgui.button(.init(pos.x, pos.y, width, height), text);
    }

    pub fn init(gpa: std.mem.Allocator, node: *ui.Node, inspector: *Inspector) !Entry {
        const children = try gpa.alloc(Entry, node.children.items.len);
        for (node.children.items, 0..) |child, i| {
            children[i] = try Entry.init(gpa, child, inspector);
        }
        const info = try node.vtable.type_info(node.manager, node, gpa);
        const state = if (info.properties) |p| try gpa.alloc(InfoState, p.len) else null;
        if (info.properties) |p| {
            for (p, 0..) |prop, i| {
                switch (prop) {
                    .float => {
                        state.?[i] = try InfoState.floatState(gpa);
                    },
                    .int => {
                        state.?[i] = .{ .int = .{} };
                    },
                    .vector => {
                        state.?[i] = try InfoState.vecState(gpa);
                    },
                    else => {
                        state.?[i] = .none;
                    },
                }
            }
        }
        return .{
            .info = info,
            .state = state,
            .inspector = inspector,
            .node = node,
            .children = children,
            .function_state = try .init(gpa, node.space.offset),
            .gpa = gpa,
        };
    }

    pub fn reloadChildren(this: *Entry) !void {
        var reload: bool = this.children.len != this.node.children.items.len;
        if (!reload) {
            for (this.children, 0..) |child, i| {
                if (child.node != this.node.children.items[i]) {
                    reload = true;
                    break;
                }
            }
        }
        if (reload) {
            if (this.inspector.selected_entry == this) this.inspector.selected_entry = null;
            for (this.children) |*child| {
                if (this.inspector.selected_entry == child) {
                    this.inspector.selected_entry = null;
                    std.log.debug("killing selected", .{});
                }
                child.deinit();
            }
            this.gpa.free(this.children);
            this.children = try this.gpa.alloc(Entry, this.node.children.items.len);
            for (0..this.children.len) |i| {
                this.children[i] = try .init(this.gpa, this.node.children.items[i], this.inspector);
            }
        } else {
            for (this.children) |*child| {
                try child.reloadChildren();
            }
        }
    }

    pub fn deinit(this: Entry) void {
        for (this.children) |child| {
            child.deinit();
        }
        if (this.state) |s| {
            for (s) |s2| {
                s2.deinit(this.gpa);
            }
            this.gpa.free(s);
        }
        this.function_state.deinit(this.gpa);
        this.info.deinit(this.gpa);
        this.gpa.free(this.children);
    }
};

pub fn draw(this: *@This()) !void {
    try this.reloadGraph(this.root_entry.node);
    rl.clearBackground(rl.getColor(@bitCast(rgui.getStyle(.default, .background_color))));
    if (this.is_open) {
        const source: rl.Rectangle = .init(0, 0, this.width, -this.height);
        const dest: rl.Rectangle = .init(this.width / 3, 0, this.width * 2 / 3, this.height * 2 / 3);
        this.texture.texture.drawPro(source, dest, .zero(), 0, .white);
        const bar_size: f32 = @floatFromInt(rgui.getStyle(.scrollbar, .scroll_slider_size));
        _ = rgui.scrollPanel(.init(0, 0, this.width / 3, this.height * 2 / 3), null, .init(0, 0, this.width, this.height), &this.node_list_scroll, &this.node_list_view);
        {
            rl.beginScissorMode(@trunc(this.node_list_view.x), @trunc(this.node_list_view.y), @trunc(this.node_list_view.width), @trunc(this.node_list_view.height));
            defer rl.endScissorMode();
            var i: f32 = 0;
            try this.root_entry.draw(&i, 0, this.node_list_scroll);
        }
        _ = rgui.scrollPanel(.init(0, this.height * 2 / 3, this.width / 2, this.height / 3), "Properties", .init(0, 0, this.width - bar_size, this.height), &this.prop_list_scroll, &this.prop_list_view);
        {
            rl.beginScissorMode(@trunc(this.prop_list_view.x), @trunc(this.prop_list_view.y), @trunc(this.prop_list_view.width), @trunc(this.prop_list_view.height));
            defer rl.endScissorMode();
            if (this.selected_entry) |selected| {
                // RAYGUI_WINDOWBOX_STATUSBAR_HEIGHT = 24
                try selected.drawProperties(rl.Vector2.init(0, 24 + this.height * 2 / 3).add(this.prop_list_scroll));
            }
        }
        _ = rgui.scrollPanel(.init(this.width / 2, this.height * 2 / 3, this.width / 2, this.height / 3), "Functions", .init(0, 0, this.width - bar_size, this.height), &this.func_list_scroll, &this.func_list_view);
        {
            rl.beginScissorMode(@trunc(this.func_list_view.x), @trunc(this.func_list_view.y), @trunc(this.func_list_view.width), @trunc(this.func_list_view.height));
            defer rl.endScissorMode();
            if (this.selected_entry) |selected| {
                try selected.drawFunctions(rl.Vector2.init(this.width / 2 + 5, 5 + 24 + this.height * 2 / 3).add(this.func_list_scroll), 5);
            }
        }
    } else {
        this.texture.texture.drawRec(.init(0, 0, this.width, -this.height), .zero(), .white);
    }
}

pub fn reloadGraph(this: *Inspector, root: *ui.Node) !void {
    const selected_ptr: ?*ui.Node = if (this.selected_entry) |e| e.node else null;
    if (this.root_entry.node != root) {
        this.root_entry.deinit();
        try this.setRoot(root);
        this.selected_entry = null;
    } else {
        try this.root_entry.reloadChildren();
    }
    if (selected_ptr) |ptr| {
        this.selected_entry = this.checkChildPtrs(&this.root_entry, ptr);
    }
}

pub fn checkChildPtrs(this: *Inspector, entry: *Entry, node: *ui.Node) ?*Entry {
    if (entry.node == node) return entry;
    for (entry.children) |*child| {
        if (this.checkChildPtrs(child, node)) |res| return res;
    }
    return null;
}
