const std = @import("std");
const zms_root = @import("zms");

//               Tip                     ___
//               /\                        |
//              /  \                       |
//             /    \                      |
// Left Side  /      \  Right Side         |
//           /        \                    | Length
//          /     -->  \                   |
//         /   Normal   \                  |
//        /              \                 |
//        ----------------              ___|
// Left Base    Base    Right Base

/// A point on the prism.
pub const Point = enum {
    Tip,
    LeftBase,
    RightBase,
};

/// A side of the prism.
pub const Side = enum(u2) {
    Normal,
    Left,
    Right,
    Base,
};

/// A collision prism. Depends on how big an index is for the prism and what the parent model uses as an element type for vectors.
pub fn Prism(comptime IndexType: type, comptime Element: type, comptime zms_impl: zms_root.Implementation(Element), comptime UserData: type) type {
    return struct {
        const Self = @This();
        const zms = zms_root.specialize(Element, zms_impl);
        /// Length of the prism from the tip to where it perpendicularly intersects the base.
        length: Element,
        /// Index into the model vertices for the tip point.
        tip_index: IndexType,
        /// Indices into the side directions for each triangle direction.
        side_indices: [std.math.maxInt(@typeInfo(Side).Enum.tag_type) + 1]IndexType,
        /// User data.
        user_data: UserData,

        /// Get a direction of the prism using a slice to existing directions. Assumes directions are normalized.
        pub fn getDirection(self: Self, directions: []const zms.Vec3, side: Side) zms.Vec3 {
            return directions[self.side_indices[@intFromEnum(side)]];
        }

        /// Get a point of the prism using slices to existing points and directions. Assumes directions are normalized.
        pub fn getPoint(self: Self, points: []const zms.Vec3, directions: []const zms.Vec3, point: Point) zms.Vec3 {
            switch (point) {
                .Tip => return points[self.tip_index],

                // Point fetching.
                //
                //               Tip       ___
                //               /\          |
                //              /  \         |
                //             /    \        |
                //            /      \       |
                //           /        \      | Length
                //          /     -->  \     |
                //         /   Normal   \    |
                //        /              \   |
                //        ---------------- __|
                // Left Base     Base
                //
                // We want to get the Left Base position by using only the the directions given and length.
                //
                // Let the vector between the Tip and Left Base positions be called LB.
                // If we project LB onto the Base direction and get the length of it, we get Length.
                // We also know that LB = Normal x Left * LeftSideLen.
                // This is because crossing Left into Normal will return a vector in the same direction as LB.
                // And LB must be multiplied by some unknown length (the side of the left side) in order to reach Left Base.
                // This means we get the following equation that we can simplify:
                //
                // len(proj LB onto Base) = Length.                     Initial equation.
                // len((LB dot Base) / len(Base) * Base) = Length.      Expand projection formula.
                // len(LB dot Base * Base) = Length.                    Length of Base is 1.
                // LB dot Base = Length.                                Base is the direction, LB dot Base is the length of projection so simplify out.
                // ((Normal x Left) * LeftSideLen) dot Base = Length.   Expand LB.
                // LeftSideLen * ((Normal x Left) dot Base) = Length.   Removing scalar from dot product is allowed.
                // LeftSideLen = Length / ((Normal x Left) dot Base.    Equation solved!
                //
                // Left Base = Tip + LeftSideLen * LB.                  Write Left Base in terms of above.
                //
                // The same is applicable for Right Base. The only difference is RB = Right x Normal due to the opposite directions.

                // Algorithm above for the left side.
                .LeftBase => {
                    // LB = Normal x Left.
                    const lb = self.getDirection(directions, .Normal)
                        .cross(self.getDirection(directions, .Left));
                    // Dot with base.
                    const dot = lb.dot(self.getDirection(directions, .Base));
                    // Finally, Tip + LB * (Length / dotResult) for the result.
                    return self.getPoint(points, directions, .Tip)
                        .add(lb.mul(self.length / dot));
                },

                // Algorithm above for the right side.
                .RightBase => {
                    // RB = Right x Normal.
                    const rb = self.getDirection(directions, .Right)
                        .cross(self.getDirection(directions, .Normal));
                    // Dot with base.
                    const dot = rb.dot(self.getDirection(directions, .Base));
                    // Finally, Tip + RB * (Length / dotResult) for the result.
                    return self.getPoint(points, directions, .Tip)
                        .add(rb.mul(self.length / dot));
                },
            }
        }

        /// Using 3 points, create a prism representation. Assume vertices will be given in counter-clockwise winding order.
        pub fn create(points: [3]zms.Vec3) struct {
            tip: zms.Vec3,
            normal_dir: zms.Vec3,
            left_dir: zms.Vec3,
            right_dir: zms.Vec3,
            base_dir: zms.Vec3,
            length: Element,
        } {

            // Simplify point usage.
            const p0 = points[0];
            const p1 = points[1];
            const p2 = points[2];

            // Get vectors to left and right base.
            const to_left_base = p0.createVecTo(p1);
            const to_right_base = p0.createVecTo(p2);
            const left_base_to_right_base = p1.createVecTo(p2);

            // Since to left and to right base are on the same plane, crossing leads into normal.
            const normal = to_left_base.cross(to_right_base).normalize();

            // Use the normal vector to get other directions.
            const left_dir = to_left_base.cross(normal).normalize();
            const right_dir = normal.cross(to_right_base).normalize();
            const base_dir = left_base_to_right_base.cross(normal).normalize();

            // Length is just one of the left or right sides projected onto the base direction. Since the direction is normal, dot product is sufficient.
            const length = to_left_base.dot(base_dir);
            return .{ .tip = p0, .normal_dir = normal, .left_dir = left_dir, .right_dir = right_dir, .base_dir = base_dir, .length = length };
        }
    };
}

// See img/prismCreationTest1.png and img/prismCreationTest2.png for visual.
// Note that it is Geogebra coordinates which are different.
// I use X right, Y up where Geogebra uses X right Z up. To convert from Geogebra to the coordinates here, make Y negative then swap the Y and Z positions.
test "Creation" {
    const impl = zms_root.builtinImplementationFloat(f32);
    const prisms = Prism(u16, f32, impl, void);
    const zms = zms_root.specialize(f32, impl);
    const max_error = 0.001;

    const points = [_]zms.Vec3{
        zms.vec3(1, 3, -3),
        zms.vec3(-2, 1, 0),
        zms.vec3(3, 0, 2),
    };
    var dirs: [4]zms.Vec3 = undefined;
    const prism_data = prisms.create([_]zms.Vec3{
        points[0],
        points[1],
        points[2],
    });
    dirs[0] = prism_data.normal_dir;
    dirs[1] = prism_data.left_dir;
    dirs[2] = prism_data.right_dir;
    dirs[3] = prism_data.base_dir;
    const prism = prisms{
        .tip_index = 0,
        .side_indices = [_]u16{ 0, 1, 2, 3 },
        .length = prism_data.length,
        .user_data = {},
    };
    try std.testing.expect(points[0].approxEql(prism.getPoint(&points, &dirs, .Tip), max_error));
    try std.testing.expect(points[1].approxEql(prism.getPoint(&points, &dirs, .LeftBase), max_error));
    try std.testing.expect(points[2].approxEql(prism.getPoint(&points, &dirs, .RightBase), max_error));
    try std.testing.expect(prism.getDirection(&dirs, .Normal).approxEql(zms.vec3(-0.0405, 0.8496, 0.5259), max_error));
    try std.testing.expect(prism.getDirection(&dirs, .Left).approxEql(zms.vec3(-0.7676, 0.3105, -0.5606), max_error));
    try std.testing.expect(prism.getDirection(&dirs, .Right).approxEql(zms.vec3(0.9450, 0.2034, -0.2559), max_error));
    try std.testing.expect(prism.getDirection(&dirs, .Base).approxEql(zms.vec3(-0.4062, -0.4949, 0.7682), max_error));
}
