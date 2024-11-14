pub const Model = @import("model.zig").Model;
pub const prism = @import("prism.zig");
const std = @import("std");
const zms = @import("zms");

test {
    std.testing.refAllDecls(@This());
}

const zms2 = zms.specialize(f32, zms.builtinImplementationFloat(f32));
pub fn doCross(ax: f32, ay: f32, az: f32, bx: f32, by: f32, bz: f32) callconv(.C) extern struct { x: f32, y: f32, z: f32 } {
    const ret = zms2.vec3(ax, ay, az).cross(zms2.vec3(bx, by, bz)).data;
    return .{ .x = ret[0], .y = ret[1], .z = ret[2] };
}
comptime {
    @export(doCross, .{ .name = "doCross" });
}
