namespace SpiderBuddy.Core;

/// <summary>
/// The classic leg rig (the 1.0.0 reference, spec 3.4). Eight legs; 0–3 are the near side drawn in
/// front of the body (front→back), 4–7 the far side drawn behind and darker. Body-local units:
/// +x forward, +y up away from the ledge, feet on <see cref="Ground"/>.
///
/// This is "art, not IK" — the knee model below is deliberately not a two-bone solver, because a
/// real solver picks a different elbow side as the foot crosses the body and the legs stop looking
/// like one animal. The one exception (a leg gripping a line) uses a real IK in Stage 8.
/// </summary>
public static class SpiderRig
{
    /// <summary>Feet reach down to y = −22 (hence standoff = 22).</summary>
    public const double Ground = -22;

    public const double DrawRadius = 72;
    public const double BodyLength = 46;
    public const int LegCount = 8;

    // hip, knee, foot — profile (side-on)
    static readonly V2[,] Profile =
    {
        { new( 9, -9), new( 24,  2), new( 30, -22) },   // near 0 — reaches ahead of the face
        { new( 6, -10), new( 15, -8), new( 18, -22) },  // near 1 — short, tucked under the chin
        { new( 1, -10), new( -6, -5), new( -6, -22) },  // near 2
        { new(-3, -9), new( -17, -1), new(-24, -22) },  // near 3
        { new( 7, -7), new( 21,  5), new( 26, -22) },   // far 4
        { new( 4, -8), new( 11,  1), new( 13, -22) },   // far 5
        { new(-1, -8), new( -11, 2), new(-13, -22) },   // far 6
        { new(-5, -7), new( -21, 3), new(-30, -22) },   // far 7
    };

    // hip, knee, foot — front view (facing you)
    static readonly V2[,] Front =
    {
        { new( 8, -8), new( 31, -4), new( 38, -22) },
        { new( 7, -9), new( 18,  0), new( 22, -22) },
        { new(-5, -9), new(-11, -3), new(-14, -22) },
        { new(-8, -8), new(-25, -1), new(-31, -22) },
        { new( 8, -8), new( 25, -1), new( 31, -22) },
        { new( 5, -9), new( 11, -3), new( 14, -22) },
        { new(-7, -9), new(-18,  0), new(-22, -22) },
        { new(-8, -8), new(-31, -4), new(-38, -22) },
    };

    /// <summary>A leg's rest shape at a given profile (1 = side-on, 0 = facing you).</summary>
    public static LegPose Rig(int i, double profile, LegStyle style = LegStyle.Classic)
    {
        i = M.Clamp(i, 0, LegCount - 1);
        double p = M.Clamp01(profile);
        V2 hip = V2.Lerp(Front[i, 0], Profile[i, 0], p);
        V2 knee = V2.Lerp(Front[i, 1], Profile[i, 1], p);
        V2 foot = V2.Lerp(Front[i, 2], Profile[i, 2], p);
        foot = new V2(foot.X, Ground);
        return new LegPose(hip, knee, foot);
    }

    /// <summary>
    /// Leg styles change reach (foot-x and knee offset from the hip), extra knee rise and width.
    /// Feet stay on the ledge, so long legs stand wider with higher knees (spec 3.4).
    /// </summary>
    public static LegPose Style(LegPose rest, LegStyle style, LegTuning tune)
    {
        var (reach, kneeRise, _) = tune.For(style);
        V2 hip = rest.Hip;
        V2 foot = new(hip.X + (rest.Foot.X - hip.X) * reach, Ground);
        V2 knee = new(hip.X + (rest.Knee.X - hip.X) * reach, hip.Y + (rest.Knee.Y - hip.Y) * kneeRise);
        return new LegPose(hip, knee, foot);
    }

    /// <summary>
    /// The classic knee model (spec 3.4): take the rest knee offset from the hip, rotate it by the
    /// angle the hip→foot vector has swung from rest, and scale it by how far the foot is from the
    /// hip. When the foot is closer than rest the leg *folds* with a two-bone solve, keeping the
    /// knee on the rest knee's side.
    /// </summary>
    public static V2 Knee(V2 hip, V2 foot, LegPose rest)
    {
        V2 restOffset = rest.Knee - rest.Hip;
        V2 restFootVec = rest.Foot - rest.Hip;
        double restLen = restFootVec.Length;
        V2 footVec = foot - hip;
        double d = footVec.Length;
        if (restLen < 1e-9) return hip + restOffset;

        double swing = M.AngleDelta(restFootVec.Angle, footVec.Angle);
        double reach = M.Clamp(d / restLen, 0.5, 1.3);
        reach = M.Clamp(reach, 0.5, 1.3);

        if (reach >= 0.999)
            return hip + restOffset.Rotated(swing) * reach;

        // Folded: thigh + shin keep their lengths; solve for the knee on the rest side.
        double a = restOffset.Length;
        double b = (rest.Foot - rest.Knee).Length;
        double dd = M.Clamp(d, Math.Abs(a - b) + 0.5, a + b - 0.5);
        if (dd < 1e-9 || a < 1e-9) return hip + restOffset;

        double x = (a * a - b * b + dd * dd) / (2 * dd);
        double hSq = Math.Max(0, a * a - x * x);
        double h = Math.Sqrt(hSq);

        V2 dir = footVec.Normalized;
        if (dir.LengthSquared < 1e-12) dir = restFootVec.Normalized;
        V2 perp = dir.Perp;
        // The rest knee's side decides which way the knee bends. Measured as the rest offset's
        // component along the rest foot vector's left normal, then applied to the CURRENT direction,
        // so a leg swinging round its hip keeps bending the same way at every angle.
        bool leftSide = restOffset.Dot(restFootVec.Perp) >= 0;
        V2 knee = hip + dir * x + (leftSide ? perp : -perp) * h;
        return knee;
    }

    /// <summary>A foot placed on the ledge: on the ground line, optionally spread outward.</summary>
    public static V2 GroundFoot(V2 foot, bool spread = true)
    {
        double x = foot.X;
        if (spread) x *= 1.04;
        return new V2(x, Ground);
    }

    /// <summary>Straight-line length of a leg at a profile (used by the reach limiter, spec 4.5).</summary>
    public static double LegLength(int i, double profile)
    {
        var r = Rig(i, profile);
        return r.Hip.DistanceTo(r.Foot);
    }

    public static double LongestLegLength(double profile)
    {
        double max = 0;
        for (int i = 0; i < LegCount; i++) max = Math.Max(max, LegLength(i, profile));
        return max;
    }

    /// <summary>Whether a leg is on the far side (drawn behind, darker).</summary>
    public static bool IsFar(int i) => i >= 4;

    /// <summary>
    /// The far-side index pair for a mirror. The front-view layout is symmetric under i ↔ 7−i,
    /// so at the exact moment the mirror flips the feet are re-paired and nothing jumps (spec 3.4).
    /// </summary>
    public static int Mirror(int i) => 7 - i;

    /// <summary>profileAmount(yaw) = smoothstep(|yaw|) — how far between front view and profile.</summary>
    public static double ProfileAmount(double yaw) => M.Smoothstep(Math.Abs(M.Clamp(yaw, -1, 1)));

    /// <summary>
    /// Real two-bone IK, used only for a leg gripping a line (spec 8.2): the bend side is chosen
    /// outward from the thread rather than from the rest shape.
    /// </summary>
    public static V2 KneeIk(V2 hip, V2 foot, double thigh, double shin, V2 awayFrom)
    {
        V2 d = foot - hip;
        double dist = d.Length;
        if (dist < 1e-9) return hip + new V2(0, thigh);
        dist = M.Clamp(dist, Math.Abs(thigh - shin) + 0.01, thigh + shin - 0.01);
        double x = (thigh * thigh - shin * shin + dist * dist) / (2 * dist);
        double h = Math.Sqrt(Math.Max(0, thigh * thigh - x * x));
        V2 dir = d.Normalized;
        V2 perp = dir.Perp;
        // pick the side away from the thread
        V2 mid = hip + dir * x;
        V2 outward = mid - awayFrom;
        if (perp.Dot(outward) < 0) perp = -perp;
        return mid + perp * h;
    }
}

/// <summary>The leg-style numbers (reach, knee rise, stroke width).</summary>
public readonly struct LegTuning
{
    public (double reach, double knee, double width) For(LegStyle style) => style switch
    {
        LegStyle.Slender => (1.0, 0.6, 0.75),
        LegStyle.Chunky => (0.94, 0.8, 1.55),
        LegStyle.Stubby => (0.72, 0.5, 1.25),
        LegStyle.Long => (1.22, 1.15, 0.9),
        LegStyle.Fuzzy => (1.0, 0.9, 1.2),
        LegStyle.Banded => (1.0, 0.9, 1.0),
        LegStyle.Socks => (1.0, 0.9, 1.05),
        LegStyle.Spindly => (1.12, 1.1, 0.6),
        LegStyle.Boots => (0.98, 0.85, 1.35),
        LegStyle.Robot => (1.02, 0.95, 1.3),
        LegStyle.Knobbly => (0.96, 0.95, 1.15),
        LegStyle.Striped => (1.0, 0.9, 1.0),
        LegStyle.Custom => (1.0, 0.9, 1.0),
        _ => (1.0, 0.9, 1.0),
    };
}
