using SpiderBuddy.Core;

namespace SpiderBuddy.Renderer;

/// <summary>
/// Builds poses for the contact sheet, the Studio preview and the headless tools. The live spider
/// builds its own poses in Stage 4; this is the "static spider" path used to check the art.
/// </summary>
public static class PoseBuilder
{
    /// <summary>A spider standing on a ledge at the given yaw (1 = profile, 0 = facing you).</summary>
    public static SpiderPose Standing(SpiderDesign design, double facing = 1, double scale = 0.78,
        double time = 0, double lift = 0)
    {
        var pose = new SpiderPose
        {
            Pos = V2.Zero,
            Lift = lift,
            Heading = 0,              // +x forward along the ledge, +y up off it
            Facing = facing,
            Scale = scale,
            Grounded = 1,
            Time = time,
            Name = design.Name,
            NameTag = 0
        };
        FillLegs(pose, design, facing, lift);
        return pose;
    }

    /// <summary>All eight legs from the classic rig, with the leg style applied.</summary>
    public static void FillLegs(SpiderPose pose, SpiderDesign design, double facing, double lift)
    {
        double prof = SpiderRig.ProfileAmount(facing);
        for (int i = 0; i < 8; i++)
        {
            var rest = SpiderRig.Rig(i, prof, design.Look.Legs);
            var styled = SpiderRig.Style(rest, design.Look.Legs, default);
            double reach = design.Look.LegRig.reach;
            V2 foot = new(styled.Hip.X + (styled.Foot.X - styled.Hip.X) * reach, SpiderRig.Ground + lift);
            V2 knee = SpiderRig.Knee(styled.Hip, foot, rest);
            pose.Legs[i] = new LegPose(styled.Hip, knee, foot, 0);
        }
    }

    /// <summary>A rolled-up ball (spec 6.6 roll): the egg is 20 × 17 units.</summary>
    public static SpiderPose Balled(SpiderDesign design, double spin = 0.4, double scale = 0.78, double time = 0)
    {
        var pose = Standing(design, 1, scale, time);
        pose.Ball = 1;
        pose.Spin = spin;
        pose.Stretch = 1.0;
        // the legs tuck in tight against the ball
        for (int i = 0; i < 8; i++)
        {
            var leg = pose.Legs[i];
            V2 hip = leg.Hip;
            V2 foot = hip + new V2(i < 4 ? 4.5 : -4.5, -3.5);
            pose.Legs[i] = new LegPose(hip, hip + new V2(i < 4 ? 5.5 : -5.5, -1.2), foot, 0);
        }
        return pose;
    }

    /// <summary>The hammock curl-up: every leg drawn in tight, front pair over the face.</summary>
    public static SpiderPose Curled(SpiderDesign design, double scale = 0.78, double time = 0)
    {
        var pose = Standing(design, 1, scale, time);
        pose.HeadCock = 0.3;
        for (int i = 0; i < 8; i++)
        {
            var leg = pose.Legs[i];
            V2 hip = leg.Hip;
            V2 rest = leg.Foot;
            V2 tucked = hip + (rest - hip) * 0.28 + new V2(i % 2 == 0 ? 3 : -3, 2.5);
            pose.Legs[i] = new LegPose(hip, V2.Lerp(hip, tucked, 0.6) + new V2(0, 2), tucked, 0);
        }
        pose.Stretch = 0.86;
        return pose;
    }

    /// <summary>A turn sweep: facing runs +1 → 0 → −1.</summary>
    public static IEnumerable<SpiderPose> TurnSweep(SpiderDesign design, int steps = 9, double scale = 0.78)
    {
        for (int i = 0; i < steps; i++)
        {
            double f = 1 - 2.0 * i / (steps - 1);
            yield return Standing(design, f, scale);
        }
    }

    /// <summary>Hanging on a line (Stage 8): head below the body, back four legs holding the silk.</summary>
    public static SpiderPose Hanging(SpiderDesign design, double scale = 0.78, double time = 0)
    {
        var pose = Standing(design, 1, scale, time);
        pose.Heading = -M.Pi / 2;   // head down
        pose.Grounded = 0;
        for (int i = 0; i < 8; i++)
        {
            var leg = pose.Legs[i];
            V2 hip = leg.Hip;
            // back four hold the silk above the abdomen; front four hang free
            if (i >= 2)
                pose.Legs[i] = new LegPose(hip, hip + new V2(-2, 7), new V2(-1.5, 12), 0);
            else
                pose.Legs[i] = new LegPose(hip, hip + new V2(10, -6), new V2(14, -14), 0);
        }
        return pose;
    }
}
