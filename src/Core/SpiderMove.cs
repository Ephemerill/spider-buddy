using System;

namespace SpiderBuddy.Core;

/// <summary>One foot's state. Positions are in the SPRITE frame: +x is always the head.</summary>
public struct LegState
{
    public double Phase;        // 0…1 within the global gait cycle
    public bool InSwing;
    public double SwingPh0;     // the cycle phase at which this swing started
    public V2 SwingFrom;        // sprite-frame foot at lift-off
    public V2 Foot;             // sprite-frame foot
    public double Lift;         // 0 planted … 1 raised
    public bool Forced;         // stepping back inside reach
    public double ForcedT;      // 0…1 through that step
    public double ForcedDur;    // seconds the step takes
    public V2 ForcedTo;         // where that step lands
    public V2 ForcedFrom;       // where that step began
    public V2 LastWorldFoot;    // the foot's world position — authoritative while planted
    public bool HasWorld;       // LastWorldFoot is meaningful
}

/// <summary>
/// The classic tetrapod gait (spec 4.5) — the 1.0.0 leg system, which is the reference and must not
/// be "improved". Four legs swing while four stay planted; planted feet hold still in the WORLD
/// while the body moves over them.
/// </summary>
public sealed class GaitDriver
{
    public const double StrideLength = 28;     // body units per gait cycle
    public const double SwingDuty = 0.34;      // fraction of the cycle a leg is in the air
    public const double FootJolt = 26000;      // px/s² — the last word on the feet
    public const double ReachLimit = 1.25;     // no planted foot past legLength × this
    public const double ReachShare = 0.94;     // where an over-reached foot steps to
    public const double HandoffTime = 0.26;    // the surface hand-off window
    public const double LongStride = 45;       // strides beyond this need reach slack
    public const double StepOutAt = 1.12;      // planted feet step before they reach the limit

    public double Cycle;                       // 0…1, advances with distance walked
    public readonly LegState[] Legs = new LegState[8];
    public double Stride;
    public double HalfStride;
    public double Cadence => Math.Abs(Stride) < 1e-9 ? 0 : Stride;

    /// <summary>Each leg's own full length (thigh + shin), refreshed every update.</summary>
    public readonly double[] LegLen = new double[8];

    public double LastDTheta;                  // diagnostics
    public double LastFacing;                  // the facing the stored feet are expressed in

    // ---------------------------------------------------------------- grouping

    /// <summary>
    /// The tetrapod split: legs alternate along each side, and the two sides are offset — 0 and 2
    /// share a group, and so do 0 and 5 (spec 4.5).
    /// </summary>
    public static int Group(int i)
    {
        int k = i % 4;
        bool near = i < 4;
        return ((k % 2 == 0) == near) ? 0 : 1;
    }

    /// <summary>Spec 4.5: half a cycle between the groups, three hundredths between neighbours.</summary>
    public static double PhaseOffset(int i)
    {
        int k = i % 4;
        return (Group(i) == 0 ? 0.0 : 0.5) + (3 - k) * 0.03;
    }

    public static double LegPhase(int i, double cycle)
    {
        double p = cycle + PhaseOffset(i);
        p -= Math.Floor(p);
        return p;
    }

    // ---------------------------------------------------------------- update

    /// <summary>
    /// Advance the legs one frame.
    /// </summary>
    /// <param name="distanceWalked">How far the body moved along the surface this frame.</param>
    /// <param name="bodyMotionWorld">The body's world motion, lift included.</param>
    /// <param name="dTheta">How much the DRAWN heading turned this frame.</param>
    /// <param name="surfaceMotion">World motion of the surface itself (a window being dragged).</param>
    public void Update(double distanceWalked, V2 bodyMotionWorld, double dTheta, V2 surfaceMotion,
        V2 bodyOrigin, double heading, double facing, double profile, LegStyle style, LegTuning tune,
        double scale, bool walking, double dt)
    {
        LastDTheta = dTheta;

        double stride = Math.Max(1e-6, StrideLength * tune.For(style).reach * scale);
        Stride = stride;
        HalfStride = stride * 0.5;

        // cycle advance per frame = speed·dt / stride
        double advance = distanceWalked / stride;
        Cycle = (Cycle + advance) % 1.0;
        if (Cycle < 0) Cycle += 1;

        // Body motion expressed in the SPRITE frame, where +x is always the head — the renderer
        // mirrors the whole sprite, so a foot's x flips with the facing.
        double fs = facing < 0 ? -1 : 1;

        // At the mirror the legs re-pair: leg i takes the place of leg 7−i (spec 4.7, classic). The
        // stored feet stay put in the world; only their owners swap.
        if (LastFacing != 0 && fs != LastFacing)
        {
            // The sprite mirrors, so a sprite-frame x flips sign at the same moment; then the legs
            // re-pair. Together the feet stay exactly where they are in the world (spec 4.7).
            for (int a = 0; a < 4; a++)
            {
                int b = 7 - a;
                var la = Mirror(Legs[a]);
                var lb = Mirror(Legs[b]);
                (Legs[a], Legs[b]) = (lb, la);
                (LegLen[a], LegLen[b]) = (LegLen[b], LegLen[a]);
            }
        }
        LastFacing = fs;
        _origin = bodyOrigin;
        _heading = heading;
        _fs = fs;

        double invScale = 1 / Math.Max(scale, 1e-6);
        V2 overFeet = bodyMotionWorld.Rotated(-(heading + dTheta)) * invScale;
        overFeet = new V2(overFeet.X * fs, overFeet.Y);
        V2 surfaceLocal = surfaceMotion.Rotated(-(heading + dTheta)) * invScale;
        surfaceLocal = new V2(surfaceLocal.X * fs, surfaceLocal.Y);

        for (int i = 0; i < 8; i++)
        {
            ref var leg = ref Legs[i];
            var rest = SpiderRig.Style(SpiderRig.Rig(i, profile, style), style, tune);
            V2 restSpot = rest.Foot;
            double phase = LegPhase(i, Cycle);
            double phaseOld = leg.Phase;
            leg.Phase = phase;

            // ---- a step taken because the foot ran out of reach plays on its own clock, so the gait
            // window can never interrupt it (spec 4.5.4 — a step, never a slide).
            if (leg.Forced)
            {
                leg.ForcedT = M.Clamp01(leg.ForcedT + dt / Math.Max(1e-3, leg.ForcedDur));
                double uu = M.Smoothstep(leg.ForcedT);
                V2 p2 = V2.Lerp(leg.ForcedFrom, leg.ForcedTo, uu);
                leg.Foot = new V2(p2.X, restSpot.Y);
                leg.Lift = Math.Sin(leg.ForcedT * M.Pi);
                leg.InSwing = true;
                if (leg.ForcedT >= 1)
                {
                    leg.Forced = false;
                    leg.InSwing = false;
                    leg.Foot = leg.ForcedTo;
                    leg.Lift = 0;
                    leg.SwingPh0 = phase;
                }
                ClampReach(ref leg, i, profile, style, tune, stepOut: false);
                continue;
            }


            bool inWindow = walking && phase < SwingDuty;

            // A step that would begin with the clock already part-way through its window waits for
            // the next one (skipSwing). Entering the window from the stance side is the tell.
            bool enteringWindow = inWindow && (phaseOld >= SwingDuty || phaseOld < 1e-9);
            if (inWindow && !leg.InSwing && !enteringWindow) inWindow = false;

            if (inWindow)
            {
                if (!leg.InSwing)
                {
                    leg.InSwing = true;
                    leg.SwingPh0 = phase;
                    leg.SwingFrom = leg.Foot;
                }

                double span = SwingDuty - leg.SwingPh0;
                double u = span <= 1e-9 ? 1 : M.Clamp01((phase - leg.SwingPh0) / span);

                // Placed half a stride ahead of its rest spot, so the stance covers ±stride/2.
                V2 target = restSpot + new V2(HalfStride, 0);
                V2 pos = V2.Lerp(leg.SwingFrom, target, M.Smoothstep(u));
                leg.Foot = new V2(pos.X, restSpot.Y);
                leg.Lift = Math.Sin(u * M.Pi);

                if (u >= 0.999) { leg.InSwing = false; leg.Foot = target; leg.Lift = 0; }
            }
            else
            {
                // Landing closes the swing; from here the foot is planted in the world, and its local
                // position is re-derived from that world position every frame (footWorld, Swift),
                // so the body can move over it without any accumulated error.
                if (leg.InSwing) { leg.InSwing = false; leg.Lift = 0; }

                // Held in the world: undo the body's rotation and its motion over the foot, and the
                // surface's own motion for a dragged window (spec 4.5.1).
                leg.Foot = leg.Foot.Rotated(-dTheta) - (overFeet - surfaceLocal);
                leg.Lift = M.Approach(leg.Lift, 0, 16, dt);

                // The local y wanders with the body's bob (the leg flexing as the body rides over it),
                // which is not an error; only a foot left well off the ledge is eased back.
                if (Math.Abs(leg.Foot.Y - SpiderRig.Ground) > 4)
                    leg.Foot = new V2(leg.Foot.X, M.Approach(leg.Foot.Y, SpiderRig.Ground, 14, dt));

                // Turning on the spot (spec 4.5.8): the body can swing round faster than a planted
                // foot can hold its place, so a foot carried off the ledge line steps round in the
                // usual waves instead of being dragged along the surface.
                // The bob alone moves the local y by ±1.8; anything beyond that is the ledge curving
                // away under the foot (a corner), so the foot steps rather than being dragged.
                if (Math.Abs(leg.Foot.Y - SpiderRig.Ground) > 2.2 && !leg.Forced)
                {
                    leg.Forced = true;
                    leg.ForcedT = 0;
                    leg.ForcedDur = 0.16;
                    leg.SwingFrom = leg.Foot;
                    leg.ForcedTo = restSpot;
                    leg.InSwing = true;
                }
            }

            // A leg's full length is thigh + shin: the standing pose is bent, so the rest hip→foot
            // distance is much shorter than what the leg can actually reach.
            double legLen = rest.Knee.DistanceTo(rest.Hip) + rest.Foot.DistanceTo(rest.Knee);
            LegLen[i] = legLen;

            // limitReach (spec 4.5.4). A foot about to reach the limit takes a step first, so the
            // clamp is a last word that ordinary walking never needs.
            ClampReach(ref leg, i, profile, style, tune, stepOut: true);
        }

        if (!walking) Settle(profile, style, tune);
    }

    // ---------------------------------------------------------------- helpers

    /// <summary>
    /// A hand-off (spec 4.5.7): the surface under the spider changed, so every foot eases from where
    /// it is to its place on the new one over handoffTime — a step, never a jump.
    /// </summary>
    public void BeginHandoff(double profile, LegStyle style, LegTuning tune)
    {
        for (int i = 0; i < 8; i++)
        {
            ref var leg = ref Legs[i];
            var rest = SpiderRig.Style(SpiderRig.Rig(i, profile, style), style, tune);
            if (leg.Foot.DistanceTo(rest.Foot) < 0.5) continue;
            leg.Forced = true;
            leg.ForcedT = 0;
            leg.ForcedDur = HandoffTime;
            leg.ForcedFrom = leg.Foot;
            leg.ForcedTo = rest.Foot;
            leg.InSwing = true;
        }
    }

    V2 _origin;
    double _heading;
    double _fs = 1;

    /// <summary>A sprite-frame point in world coordinates.</summary>
    V2 ToWorld(V2 local)
    {
        if (_fs < 0) local = new V2(-local.X, local.Y);
        return _origin + local.Rotated(_heading);
    }

    /// <summary>A world point in the sprite frame.</summary>
    V2 ToLocal(V2 world)
    {
        V2 l = (world - _origin).Rotated(-_heading);
        return _fs < 0 ? new V2(-l.X, l.Y) : l;
    }

    /// <summary>A leg mirrored in the sprite frame.</summary>
    static LegState Mirror(LegState leg)
    {
        leg.Foot = new V2(-leg.Foot.X, leg.Foot.Y);
        leg.SwingFrom = new V2(-leg.SwingFrom.X, leg.SwingFrom.Y);
        leg.ForcedTo = new V2(-leg.ForcedTo.X, leg.ForcedTo.Y);
        return leg;
    }

    /// <summary>No foot past legLength × 1.25 from its drawn hip (spec 4.5.4).</summary>
    void ClampReach(ref LegState leg, int i, double profile, LegStyle style, LegTuning tune, bool stepOut)
    {
        var rest = SpiderRig.Style(SpiderRig.Rig(i, profile, style), style, tune);
        double legLen = rest.Knee.DistanceTo(rest.Hip) + rest.Foot.DistanceTo(rest.Knee);
        LegLen[i] = legLen;
        V2 hip = rest.Hip;
        V2 away = leg.Foot - hip;
        double most = legLen * ReachLimit + Math.Max(Stride - LongStride, 0) * 0.5;
        if (stepOut && !leg.InSwing && !leg.Forced && away.Length > legLen * StepOutAt)
        {
            leg.Forced = true;
            leg.ForcedT = 0;
            leg.ForcedDur = 0.16;
            leg.ForcedFrom = leg.Foot;
            // Step to the leg's own ledge spot: a radial point along hip→foot would sit *above*
            // the ledge and the foot would land in mid-air.
            leg.ForcedTo = rest.Foot;
            leg.InSwing = true;
            return;
        }
        if (away.Length > most && away.Length > 1e-9)
            leg.Foot = hip + away.Normalized * most;
    }

    /// <summary>Put every foot on its rest spot, planted (used before the first frame).</summary>
    public void PlantAtRest(double profile, LegStyle style, LegTuning tune)
    {
        for (int i = 0; i < 8; i++)
        {
            var rest = SpiderRig.Style(SpiderRig.Rig(i, profile, style), style, tune);
            Legs[i].Foot = rest.Foot;
            Legs[i].SwingFrom = rest.Foot;
            Legs[i].HasWorld = false;
            Legs[i].InSwing = false;
            Legs[i].Forced = false;
            Legs[i].Lift = 0;
            Legs[i].Phase = LegPhase(i, Cycle);
            LegLen[i] = rest.Knee.DistanceTo(rest.Hip) + rest.Foot.DistanceTo(rest.Knee);
        }
    }

    /// <summary>The knee for a leg, from its current foot (spec 3.4).</summary>
    public V2 KneeFor(int i, double profile, LegStyle style, LegTuning tune)
    {
        var rest = SpiderRig.Style(SpiderRig.Rig(i, profile, style), style, tune);
        return SpiderRig.Knee(rest.Hip, Legs[i].Foot, rest);
    }

    /// <summary>
    /// A foot left mid-stride when a walk stops takes one small step to its place, one leg at a time
    /// (never a slide) — spec 4.5.6.
    /// </summary>
    void Settle(double profile, LegStyle style, LegTuning tune)
    {
        for (int i = 0; i < 8; i++)
        {
            ref var leg = ref Legs[i];
            if (leg.InSwing || leg.Forced) continue;
            var rest = SpiderRig.Style(SpiderRig.Rig(i, profile, style), style, tune);
            if (leg.Foot.DistanceTo(rest.Foot) <= 2.0) { leg.Lift = 0; continue; }

            // one leg at a time, so a stop never reads as a shuffle
            bool busy = false;
            for (int k = 0; k < 8; k++) if (Legs[k].Forced) { busy = true; break; }
            if (busy) continue;

            leg.Forced = true;
            leg.ForcedT = 0;
            leg.ForcedDur = 0.24;       // settleFoot's step
            leg.SwingFrom = leg.Foot;
            leg.ForcedTo = rest.Foot;
            leg.InSwing = true;
        }
    }
}
