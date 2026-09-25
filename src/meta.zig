pub const std = @import("std");

pub fn ErrorSet(comptime T: type) ?type {
    if (@typeInfo(T) != .error_union) return null;
    return @typeInfo(T).error_union.error_set;
}
pub fn FnErrorSet(comptime T: type) ?type {
    const ret = @typeInfo(@typeInfo(T).@"fn".return_type.?);
    if (ret == .error_union) return ret.error_union.error_set;
    return error{};
}
pub fn FnErrorUnionCompound(comptime Error: type, comptime Ret: type) type {
    const err_ret = @typeInfo(@typeInfo(Error).@"fn".return_type.?);
    if (err_ret == .error_union) return err_ret.error_union.error_set!Ret;
    return Ret;
}

pub fn EnumCompound(comptime Enum: type, comptime extra: []const []const u8) type {
    const len: comptime_int = @typeInfo(Enum).@"enum".fields.len +| extra.len -| 2;
    const Tag = std.math.IntFittingRange(0, len);
    return @Enum(Tag, .exhaustive, std.meta.fieldNames(Enum) ++ extra, &std.simd.iota(Tag, len +| 2));
}

/// Requires the enum backing value to be sequential
pub fn nextEnumValueWrap(value: anytype) @TypeOf(value) {
    const info = @typeInfo(@TypeOf(value)).@"enum";
    const idx = @intFromEnum(value);
    if (idx + 1 >= info.fields.len) return @enumFromInt(info.fields[0].value);
    return @enumFromInt(idx + 1);
}

/// Requires the enum backing value to be sequential
pub fn prevEnumValueWrap(value: anytype) @TypeOf(value) {
    const info = @typeInfo(@TypeOf(value)).@"enum";
    const idx = @intFromEnum(value);
    if (idx == 0) return @enumFromInt(info.fields[info.fields.len - 1].value);
    return @enumFromInt(idx - 1);
}
