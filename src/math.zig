const std = @import("std");

pub fn NumVec2(comptime T: type) type {
    return struct {
        pub const Type = T;
        x: T,
        y: T,

        pub fn eql(this: @This(), other: @This()) bool {
            return this.x == other.x and this.y == other.y;
        }

        pub fn lEql(this: @This(), x: T, y: T) bool {
            return this.x == x and this.y == y;
        }

        pub fn div(this: @This(), other: @This()) @This() {
            return .{ .x = this.x / other.x, .y = this.y / other.y };
        }
        pub fn divValue(this: @This(), value: T) @This() {
            return .{ .x = this.x / value, .y = this.y / value };
        }
        pub fn lDiv(this: @This(), x: T, y: T) @This() {
            return .{ .x = this.x / x, .y = this.y / y };
        }
        pub fn floorDiv(this: @This(), other: @This()) @This() {
            return .{ .x = @divFloor(this.x, other.x), .y = @divFloor(this.y, other.y) };
        }
        pub fn floorDivValue(this: @This(), value: T) @This() {
            return .{ .x = @divFloor(this.x, value), .y = @divFloor(this.y, value) };
        }
        pub fn rem(this: @This(), other: @This()) @This() {
            return .{ .x = @rem(this.x, other.x), .y = @rem(this.y, other.y) };
        }
        pub fn remValue(this: @This(), value: T) @This() {
            return .{ .x = @rem(this.x, value), .y = @rem(this.y, value) };
        }
        pub fn sub(this: @This(), other: @This()) @This() {
            return .{ .x = this.x - other.x, .y = this.y - other.y };
        }
        pub fn multValue(this: @This(), value: T) @This() {
            return .{ .x = this.x * value, .y = this.y * value };
        }
        pub fn add(this: @This(), other: @This()) @This() {
            return .{ .x = this.x + other.x, .y = this.y + other.y };
        }
        pub fn lAdd(this: @This(), x: T, y: T) @This() {
            return .{ .x = this.x + x, .y = this.y + y };
        }

        pub const zero: @This() = .{ .x = 0, .y = 0 };
        pub const max: @This() = .{ .x = maxNum(T), .y = maxNum(T) };
        pub const min: @This() = .{ .x = minNum(T), .y = minNum(T) };
    };
}
pub const IVec2 = NumVec2(i32);
pub const LVec2 = NumVec2(i64);
pub const FVec2 = NumVec2(f32);

pub fn maxNum(comptime T: type) T {
    comptime {
        switch (@typeInfo(T)) {
            .int, .comptime_int => return std.math.maxInt(T),
            .float, .comptime_float => return std.math.floatMax(T),
            else => @compileError("Type not a number"),
        }
    }
}
pub fn minNum(comptime T: type) T {
    comptime {
        switch (@typeInfo(T)) {
            .int, .comptime_int => return std.math.minInt(T),
            .float, .comptime_float => return std.math.floatMin(T),
            else => @compileError("Type not a number"),
        }
    }
}

pub fn OperableNumber(comptime T: type) type {
    return struct {
        value: T,

        pub fn add(this: *@This(), value: T) void {
            this.value += value;
        }
        pub fn sub(this: *@This(), value: T) void {
            this.value -= value;
        }
        pub fn mult(this: *@This(), value: T) void {
            this.value *= value;
        }
        pub fn div(this: *@This(), value: T) void {
            this.value = @divExact(this.value, value);
        }
        pub fn divFloor(this: *@This(), value: T) void {
            this.value = @divFloor(this.value, value);
        }
    };
}
