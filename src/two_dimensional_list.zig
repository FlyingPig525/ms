const std = @import("std");

pub fn StackTwoDimensionalList(comptime T: type, comptime width: i32, comptime height: i32) type {
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

pub fn TwoDimensionalList(comptime T: type) type {
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
            const errs = @typeInfo(@typeInfo(@TypeOf(func)).@"fn".return_type.?) == .error_union;
            blk: {
                a[0] = getFn(this.*, cell_x - 1, cell_y - 1) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x - 1, .y = cell_y - 1 };
                if (errs) try @call(.auto, func, a) else @call(.auto, func, a);
            }
            blk: {
                a[0] = getFn(this.*, cell_x, cell_y - 1) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x, .y = cell_y - 1 };
                if (errs) try @call(.auto, func, a) else @call(.auto, func, a);
            }
            blk: {
                a[0] = getFn(this.*, cell_x + 1, cell_y - 1) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x + 1, .y = cell_y - 1 };
                if (errs) try @call(.auto, func, a) else @call(.auto, func, a);
            }
            blk: {
                a[0] = getFn(this.*, cell_x + 1, cell_y) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x + 1, .y = cell_y };
                if (errs) try @call(.auto, func, a) else @call(.auto, func, a);
            }
            blk: {
                a[0] = getFn(this.*, cell_x + 1, cell_y + 1) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x + 1, .y = cell_y + 1 };
                if (errs) try @call(.auto, func, a) else @call(.auto, func, a);
            }
            blk: {
                a[0] = getFn(this.*, cell_x, cell_y + 1) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x, .y = cell_y + 1 };
                if (errs) try @call(.auto, func, a) else @call(.auto, func, a);
            }
            blk: {
                a[0] = getFn(this.*, cell_x - 1, cell_y + 1) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x - 1, .y = cell_y + 1 };
                if (errs) try @call(.auto, func, a) else @call(.auto, func, a);
            }
            blk: {
                a[0] = getFn(this.*, cell_x - 1, cell_y) catch break :blk;
                a[1] = AdjacentInformation{ .list = this, .x = cell_x - 1, .y = cell_y };
                if (errs) try @call(.auto, func, a) else @call(.auto, func, a);
            }
        }
    };
}
