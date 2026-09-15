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
    this.root_entry.deinit(this.gpa);
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

        pub const FloatState = struct {
            // not an array to conserve size
            str: [:0]u8,
            editing: bool = false,
            accessed: bool = false,
        };

        pub fn deinit(this: InfoState, gpa: std.mem.Allocator) void {
            switch (this) {
                .float => |f| {
                    gpa.free(f.str);
                },
                else => {},
            }
        }

        pub fn floatState(gpa: std.mem.Allocator) !InfoState {
            return .{ .float = .{
                .str = try gpa.allocSentinel(u8, 32, 0),
            } };
        }
    };

    pub fn draw(this: *Entry, gpa: std.mem.Allocator, index: *f32, depth: f32, offset: rl.Vector2) !void {
        const btn_off: f32 = if (this.children.len != 0) 30 else 0;
        if (this.children.len != 0) {
            const icon = if (this.open) rgui.IconName.arrow_down else rgui.IconName.arrow_right;
            if (rgui.button(.init(offset.x + 15 * depth, offset.y + 30 * index.*, 30, 30), rgui.iconText(@intFromEnum(icon), ""))) {
                this.open = !this.open;
            }
        }
        const name = if (this.node.id) |i| try std.mem.concatWithSentinel(gpa, u8, &.{ "\"", i, "\" ", this.info.name }, 0) else this.info.name;
        defer if (this.node.id != null) gpa.free(name);
        const size: f32 = @floatFromInt(rgui.getTextWidth(name) + (rgui.getStyle(.button, .text_padding) * 2));
        const width = if (size > this.inspector.width) size else (this.inspector.width / 3) - btn_off - (depth * 15);
        if (rgui.button(.init(offset.x + btn_off + (15 * depth), offset.y + 30 * index.*, width, 30), name)) {
            this.inspector.selected_entry = this;
        }
        if (this.open) {
            for (this.children) |*child| {
                index.* += 1;
                try child.draw(gpa, index, depth + 1, offset);
            }
        }
    }

    pub fn drawProperties(this: *Entry, offset: rl.Vector2, gpa: std.mem.Allocator) !void {
        if (this.info.properties) |p| {
            const state = this.state.?;
            var i: f32 = 0;
            for (p, 0..) |prop, idx| {
                switch (prop) {
                    .boolean => |b| {
                        _ = rgui.checkBox(.init(5, 5 + offset.y + i * 30, 30, 30), b.name, b.ptr);
                    },
                    .int => |int| {
                        _ = rgui.valueBox(.init(5, 5 + offset.y + i * 30, 300, 30), int.name, int.ptr, std.math.minInt(i32), std.math.maxInt(i32), state[idx].int.editing);
                    },
                    .float => |f| {
                        if (!state[idx].float.accessed) {
                            // holy cursed
                            @memset(state[idx].float.str, 0);
                            _ = try std.fmt.bufPrintZ(state[idx].float.str, "{d:0<0.2}", .{f.ptr.*});
                            state[idx].float.accessed = true;
                        }
                        const width: f32 = @floatFromInt(rgui.getTextWidth(f.name));
                        if (rgui.valueBoxFloat(.init(5 + width, 5 + offset.y + i * 30, 300, 30), f.name, state[idx].float.str, f.ptr, state[idx].float.editing) > 0) {
                            state[idx].float.editing = !state[idx].float.editing;
                        }
                    },
                    .string => |s| {
                        const width: f32 = @floatFromInt(rgui.getTextWidth(s.name) + rgui.getTextWidth(": \"") + rgui.getTextWidth(s.ptr) + rgui.getTextWidth("\"") + rgui.getStyle(.button, .text_padding) * 2);
                        const concat = try std.mem.concatWithSentinel(gpa, u8, &.{ s.name, ": \"", s.ptr, "\"" }, 0);
                        defer gpa.free(concat);
                        _ = rgui.label(.init(5, 5 + offset.y + i * 30, width, 10), concat);
                    },
                    else => {},
                }
                i += 1;
            }
        }
    }

    pub fn drawFunctions(this: *Entry, offset: rl.Vector2, gap: f32, _: std.mem.Allocator) !void {
        if (button(offset, 30, "Recalculate Node Graph")) {
            this.node.recalculateNodeGraphSize() catch |err| std.log.err("error recalc {any}", .{ err });
        }
        const move_width = rgui.getTextWidth("Move") + rgui.getStyle(.button, .text_padding) * 3;
        if (button(offset.add(.init(0, 30 + gap)), 30, "Move")) {
            this.node.move(this.function_state.move_vec) catch |err| std.log.err("err move {any}", .{ err });
        }
        const off: f32 = @as(f32, @floatFromInt(move_width + rgui.getStyle(.button, .border_width) * 2)) + gap;
        const move = &this.function_state.move_vec;
        const move_x = &this.function_state.move_x;
        if (!move_x.accessed) {
            // holy cursed
            @memset(move_x.str, 0);
            _ = try std.fmt.bufPrintZ(move_x.str, "{d:0<0.2}", .{ move.x });
            move_x.accessed = true;
        }
        if (rgui.valueBoxFloat(.init(offset.x + off, offset.y + 30 + gap, 100, 30), "x", move_x.str, &move.x, move_x.editing) > 0) {
            move_x.editing = !move_x.editing;
        }

        const move_y = &this.function_state.move_y;
        if (!move_y.accessed) {
            // holy cursed
            @memset(move_y.str, 0);
            _ = try std.fmt.bufPrintZ(move_y.str, "{d:0<0.2}", .{ move.y });
            move_y.accessed = true;
        }
        // i dont know why the actual width of the other valueboxfloat isnt 100, when it should be
        if (rgui.valueBoxFloat(.init(offset.x + off * 2 + 65, offset.y + 30 + gap, 100, 30), "y", move_y.str, &move.y, move_y.editing) > 0) {
            move_y.editing = !move_y.editing;
        }


        //if (rgui.valueBox(.init(offset.x + off, offset.y + 30 + gap, width, 30), &this.function_state.move_vec.x
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
        const info = try node.vtable.type_info(node.manager, gpa);
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
        };
    }

    pub fn deinit(this: Entry, gpa: std.mem.Allocator) void {
        for (this.children) |child| {
            child.deinit(gpa);
        }
        if (this.state) |s| {
            for (s) |s2| {
                s2.deinit(gpa);
            }
            gpa.free(s);
        }
        this.function_state.deinit(gpa);
        this.info.deinit(gpa);
        gpa.free(this.children);
    }
};

pub fn draw(this: *@This()) !void {
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
            try this.root_entry.draw(this.gpa, &i, 0, this.node_list_scroll);
        }
        _ = rgui.scrollPanel(.init(0, this.height * 2 / 3, this.width / 2, this.height / 3), "Properties", .init(0, 0, this.width - bar_size, this.height), &this.prop_list_scroll, &this.prop_list_view);
        {
            rl.beginScissorMode(@trunc(this.prop_list_view.x), @trunc(this.prop_list_view.y), @trunc(this.prop_list_view.width), @trunc(this.prop_list_view.height));
            defer rl.endScissorMode();
            if (this.selected_entry) |selected| {
                // RAYGUI_WINDOWBOX_STATUSBAR_HEIGHT = 24
                try selected.drawProperties(rl.Vector2.init(0, 24 + this.height * 2 / 3).add(this.prop_list_scroll), this.gpa);
            }
        }
        _ = rgui.scrollPanel(.init(this.width / 2, this.height * 2 / 3, this.width / 2, this.height / 3), "Functions", .init(0, 0, this.width - bar_size, this.height), &this.func_list_scroll, &this.func_list_view);
        {
            rl.beginScissorMode(@trunc(this.func_list_view.x), @trunc(this.func_list_view.y), @trunc(this.func_list_view.width), @trunc(this.func_list_view.height));
            defer rl.endScissorMode();
            if (this.selected_entry) |selected| {
                try selected.drawFunctions(rl.Vector2.init(this.width / 2 + 5, 5 + 24 + this.height * 2 / 3).add(this.func_list_scroll), 5, this.gpa);
            }
        }
    } else {
        this.texture.texture.drawRec(.init(0, 0, this.width, -this.height), .zero(), .white);
    }
}
