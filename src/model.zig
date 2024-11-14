const std = @import("std");
const zmsSpecialize = @import("zms").specialize;

pub fn Model(comptime Element: type) type {
    return struct {
        const zms = zmsSpecialize(Element);

        ///
        points: std.ArrayList(zms.Vec3),
        vectors: std.ArrayList(zms.Vec3),
    };
}

test {}
