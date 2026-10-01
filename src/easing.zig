const std = @import("std");
const rl = @import("raylib");

pub const Easing = enum {
    linear,
    isine,
    osine,
    iosine,

    pub fn multiplier(easing: Easing, time: f32) f32 {
        switch (easing) {
            .linear => return time,
            .isine => {
                return 1 - @cos((time * std.math.pi) / 2);
            },
            .osine => {
                return @sin((time * std.math.pi) / 2);
            },
            .iosine => {
                return -(@cos(time * std.math.pi) - 1) / 2;
            },
        }
    }
};

pub fn Eased(comptime T: type) type {
    return struct {
        last_value: T,
        current_value: T,
        ending_value: T,
        time: f32 = 0,
        len: f32 = 0,
        easing: Easing = .linear,

        pub fn init(value: T) @This() {
            return .{
                .last_value = value,
                .current_value = value,
                .ending_value = value,
            };
        }

        pub fn set(this: *@This(), value: T) void {
            this.last_value = value;
            this.current_value = value;
            this.ending_value = value;
            this.time = 0;
            this.len = 0;
        }

        pub fn interpolate(this: *@This(), easing: Easing, length: f32, to_value: T) void {
            this.last_value = this.current_value;
            this.ending_value = to_value;
            this.time = 0;
            this.easing = easing;
            this.len = length;
        }

        pub fn tick(this: *@This(), dt: f32) void {
            if (this.len == 0) return;
            this.time += dt;
            if (this.time >= this.len) {
                this.current_value = this.ending_value;
                this.len = 0;
                return;
            }
            this.current_value = ((this.ending_value - this.last_value) * this.easing.multiplier(this.time / this.len)) + this.last_value;
        }
    };
}

pub const EVector2 = struct {
    x: Eased(f32),
    y: Eased(f32),

    pub fn init(vec: rl.Vector2) EVector2 {
        return .{
            .x = .init(vec.x),
            .y = .init(vec.y),
        };
    }
    pub fn toVec2(this: EVector2) rl.Vector2 {
        return .init(this.x.current_value, this.y.current_value);
    }

    pub fn targetVec(this: EVector2) rl.Vector2 {
        return .init(this.x.ending_value, this.y.ending_value);
    }

    pub fn interpolate(this: *EVector2, easing: Easing, length: f32, to: rl.Vector2) void {
        this.x.interpolate(easing, length, to.x);
        this.y.interpolate(easing, length, to.y);
    }

    pub fn tick(this: *EVector2, dt: f32) void {
        this.x.tick(dt);
        this.y.tick(dt);
    }

    pub fn set(this: *EVector2, x: f32, y: f32) void {
        this.x.set(x);
        this.y.set(y);
    }
};
