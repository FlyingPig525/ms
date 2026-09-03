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
