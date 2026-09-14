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
panel_view: rl.Rectangle = .init(0, 0, 0, 0),
panel_scroll: rl.Vector2 = .zero(),

const l = "Hello world!";
pub fn init(gpa: std.mem.Allocator, width: f32, height: f32) !@This() {
    return .{
        .gpa = gpa,
        .width = width,
        .height = height,
        .texture = try .init(@intFromFloat(width), @intFromFloat(height)),
        .root_entry = undefined,
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
    selected: bool = false,
    label: [:0]const u8,
    inspector: *Inspector,
    node: *ui.Node,
    children: []Entry,

    pub fn draw(this: *Entry, index: *f32, depth: f32, offset: rl.Vector2) void {
        const btn_off: f32 = if (this.children.len != 0) 30 else 0;
        if (this.children.len != 0) {
            const icon = if (this.open) rgui.IconName.arrow_down else rgui.IconName.arrow_right;
            if (rgui.button(.init(offset.x + 15 * depth, offset.y + 30 * index.*, 30, 30), rgui.iconText(@intFromEnum(icon), ""))) {
                this.open = !this.open;
            }
        }
        const size: f32 = @floatFromInt(rgui.getTextWidth(this.label));
        const width = if (size > this.inspector.width) size else (this.inspector.width / 3) - btn_off - (depth * 15);
        if (rgui.button(.init(offset.x + btn_off + (15 * depth), offset.y + 30 * index.*, width, 30), this.label)) {
            this.selected = !this.selected;
        }
        if (this.open) {
            for (this.children) |*child| {
                index.* += 1;
                child.draw(index, depth + 1, offset);
            }
        }
    }

    pub fn init(gpa: std.mem.Allocator, node: *ui.Node, inspector: *Inspector) !Entry {
        const children = try gpa.alloc(Entry, node.children.items.len);
        for (node.children.items, 0..) |child, i| {
            children[i] = try Entry.init(gpa, child, inspector);
        }
        const info = node.vtable.type_info();
        return .{
            .label = info.name,
            .inspector = inspector,
            .node = node,
            .children = children,
        };
    }

    pub fn deinit(this: Entry, gpa: std.mem.Allocator) void {
        for (this.children) |child| {
            child.deinit(gpa);
        }
        gpa.free(this.children);
    }
};

pub fn draw(this: *@This()) !void {
    rl.clearBackground(rl.getColor(@bitCast(rgui.getStyle(.default, .background_color))));
    if (this.is_open) {
        const source: rl.Rectangle = .init(0, 0, this.width, -this.height);
        const dest: rl.Rectangle = .init(this.width / 3, 0, this.width * 2 / 3, this.height * 2 / 3);
        this.texture.texture.drawPro(source, dest, .zero(), 0, .white);
        _ = rgui.scrollPanel(.init(0, 0, this.width / 3, this.height * 2 / 3), null, .init(0, 0, this.width, this.height), &this.panel_scroll, &this.panel_view);
        {
            rl.beginScissorMode(@intFromFloat(this.panel_view.x), @intFromFloat(this.panel_view.y), @intFromFloat(this.panel_view.width), @intFromFloat(this.panel_view.height));
            defer rl.endScissorMode();
            var i: f32 = 0;
            this.root_entry.draw(&i, 0, this.panel_scroll);
        }
    } else {
        this.texture.texture.drawRec(.init(0, 0, this.width, -this.height), .zero(), .white);
    }
}
