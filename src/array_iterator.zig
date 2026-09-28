const std = @import("std");

pub fn ArrayIterator(comptime T: type, comptime array_len: usize) type {
    return struct {
        arr: [array_len]T,
        len: usize,
        idx: usize = 0,

        pub fn init(items: []const T) @This() {
            std.debug.assert(items.len <= array_len);
            var arr = @This(){
                .arr = undefined,
                .len = items.len,
            };
            @memcpy(arr.arr[0..items.len], items);
            return arr;
        }

        pub fn next(this: *@This()) ?T {
            if (this.idx >= this.len) return null;
            defer this.idx += 1;
            return this.arr[this.idx];
        }

        pub fn reset(this: *@This()) void {
            this.idx = 0;
        }
    };
}
