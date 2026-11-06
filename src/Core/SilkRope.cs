namespace SpiderBuddy.Core;

/// <summary>
/// The one rope in the product (spec 1.4). Every thread — dragline, swing line, traces,
/// hammock strands, toy tow-lines — is this solver: a Verlet chain of 14 segments (15 points).
///
/// Behaviour it must give: sags when slack, lags and whips when fired or swung on, bows when
/// the spider bounces on the end, drifts down from its anchor when released while fading.
/// </summary>
public sealed class SilkRope
{
    public const int Segments = 14;
    public const int Points = Segments + 1;      // 15
    const double Substep = 1.0 / 120.0;
    const int MaxSubsteps = 6;
    const int RelaxPasses = 10;

    public readonly V2[] P = new V2[Points];
    public readonly V2[] Prev = new V2[Points];

    /// <summary>Rest length of the whole rope.</summary>
    public double Length;

    public bool HeadPinned = true;
    public bool TailPinned = true;
    public bool Live = true;

    double _acc;
    /// <summary>Largest per-substep movement of any point — ~0 at rest, used to sleep the solver.</summary>
    public double Motion;

    public bool HeadIsTop; // purely informational: which end is the anchor

    public SilkRope()
    {
        Reset(V2.Zero, new V2(0, -100));
    }

    /// <summary>Both ends pinned, points lerped from a to b, length = |a-b|.</summary>
    public void Reset(V2 a, V2 b)
    {
        for (int i = 0; i < Points; i++)
        {
            P[i] = V2.Lerp(a, b, i / (double)Segments);
            Prev[i] = P[i];
        }
        Length = a.DistanceTo(b);
        HeadPinned = true;
        TailPinned = true;
        Live = true;
        _acc = 0;
        Motion = 0;
        HeadIsTop = b.Y <= a.Y;
    }

    /// <summary>Resample a polyline evenly to 15 points at rest; length = path length.</summary>
    public void ResetAlong(IReadOnlyList<V2> polyline)
    {
        if (polyline.Count < 2) { Reset(polyline.Count == 1 ? polyline[0] : V2.Zero, polyline.Count == 1 ? polyline[0] : V2.Zero); return; }

        // total length
        double total = 0;
        for (int i = 1; i < polyline.Count; i++) total += polyline[i - 1].DistanceTo(polyline[i]);
        Length = total;

        double step = total / Segments;
        int seg = 0;
        double segPos = 0;
        for (int i = 0; i < Points; i++)
        {
            double want = i * step;
            double walked = 0;
            seg = 0;
            for (; seg < polyline.Count - 1; seg++)
            {
                double segLen = polyline[seg].DistanceTo(polyline[seg + 1]);
                if (walked + segLen >= want - 1e-9 || seg == polyline.Count - 2)
                {
                    segPos = segLen <= 1e-9 ? 0 : (want - walked) / segLen;
                    break;
                }
                walked += segLen;
            }
            seg = Math.Min(seg, polyline.Count - 2);
            P[i] = V2.Lerp(polyline[seg], polyline[seg + 1], M.Clamp01(segPos));
            Prev[i] = P[i];
        }
        HeadPinned = true;
        TailPinned = true;
        Live = true;
        _acc = 0;
        Motion = 0;
    }

    /// <summary>
    /// Advance the solver. gravity acts downward (subtracted from y); wind pushes +x.
    /// head/tail are the targets for the pinned ends.
    /// </summary>
    public void Step(V2 head, V2 tail, double gravity, double drag, double wind, double dt)
    {
        if (!Live) return;
        Motion = 0;
        _acc += Math.Min(dt, 0.05);
        int steps = 0;
        double h = Substep;
        while (_acc >= h && steps < MaxSubsteps)
        {
            _acc -= h;
            steps++;
            Substeps(head, tail, gravity, drag, wind, h);
        }
        if (steps >= MaxSubsteps) _acc = Math.Min(_acc, h); // never let the accumulator run away

        // Re-pin both ends exactly after the substeps.
        if (HeadPinned) { P[0] = head; Prev[0] = head; }
        if (TailPinned) { P[Segments] = tail; Prev[Segments] = tail; }
    }

    void Substeps(V2 head, V2 tail, double gravity, double drag, double wind, double h)
    {
        if (HeadPinned) { P[0] = head; Prev[0] = head; }
        if (TailPinned) { P[Segments] = tail; Prev[Segments] = tail; }

        // integrate free points (Verlet): v = (p - prev) * drag; prev = p; p += v + F * h^2
        // A free end (TailPinned/HeadPinned false) integrates like any interior point.
        //
        // NOTE: spec 1.4 prints the force as (0, -gravity + wind), i.e. both terms on y. That is a
        // transcription slip: a vertical "wind" contradicts 8.7 ("blown out sideways ~15 degrees in a
        // gale") and 17j ("the wind pushes it about"). Wind is applied horizontally here and gravity
        // downward, which is the only reading consistent with the rest of the document.
        var force = new V2(wind, -gravity) * (h * h);
        for (int i = 0; i <= Segments; i++)
        {
            if (i == 0 && HeadPinned) continue;
            if (i == Segments && TailPinned) continue;
            V2 p = P[i];
            V2 v = (p - Prev[i]) * drag;
            Prev[i] = p;
            P[i] = p + v + force;
            double move = P[i].DistanceTo(p);
            if (move > Motion) Motion = move;
        }

        double rest = Length / Segments;
        bool taut = TailPinned && P[0].DistanceTo(P[Segments]) > Length * 0.96;
        double straighten = taut ? 0.16 : 0.05;

        // 10 Gauss-Seidel passes, alternating direction
        for (int pass = 0; pass < RelaxPasses; pass++)
        {
            bool fwd = (pass % 2) == 0;
            for (int k = 0; k < Segments; k++)
            {
                int i = fwd ? k : (Segments - 1 - k);
                int a = i, b = i + 1;
                V2 pa = P[a], pb = P[b];
                V2 d = pb - pa;
                double dist = d.Length;
                if (dist > rest && dist > 1e-9)
                {
                    // Only resists stretching — never pushes apart.
                    double excess = dist - rest;
                    V2 dir = d / dist;
                    bool aPinned = (a == 0 && HeadPinned) || (a == Segments && TailPinned);
                    bool bPinned = (b == 0 && HeadPinned) || (b == Segments && TailPinned);
                    if (aPinned && bPinned) continue;
                    if (aPinned) P[b] = pb - dir * excess;
                    else if (bPinned) P[a] = pa + dir * excess;
                    else { P[a] = pa + dir * (excess * 0.5); P[b] = pb - dir * (excess * 0.5); }
                }
            }

            // each interior point drifts toward the midpoint of its neighbours by `straighten`
            for (int i = 1; i < Segments; i++)
            {
                V2 mid = (P[i - 1] + P[i + 1]) * 0.5;
                P[i] = V2.Lerp(P[i], mid, straighten);
            }
        }
    }

    /// <summary>Displace point i (not a pinned end) — the pointer brushing a strand.</summary>
    public void Push(int i, V2 d)
    {
        if (i <= 0 || i >= Segments) return;
        P[i] += d;
        Prev[i] += d;
    }

    /// <summary>Nearest point index to a world position (used by pointer brushing / strand hit tests).</summary>
    public int NearestPoint(V2 p, double maxDist = double.MaxValue)
    {
        int best = 0;
        double bestD = double.MaxValue;
        for (int i = 0; i < Points; i++)
        {
            double d = P[i].DistanceSquaredTo(p);
            if (d < bestD) { bestD = d; best = i; }
        }
        return bestD <= maxDist * maxDist ? best : -1;
    }

    /// <summary>Current sag: how far the middle of the rope hangs below the straight line between its ends.</summary>
    public double Sag
    {
        get
        {
            V2 mid = V2.Lerp(P[0], P[Segments], 0.5);
            return mid.Y - P[Segments / 2].Y;
        }
    }

    /// <summary>Copy the point list for drawing.</summary>
    public void CopyPoints(V2[] into)
    {
        for (int i = 0; i < Points && i < into.Length; i++) into[i] = P[i];
    }

    public SilkRope Clone()
    {
        var r = new SilkRope
        {
            Length = Length, HeadPinned = HeadPinned, TailPinned = TailPinned, Live = Live,
            Motion = Motion, HeadIsTop = HeadIsTop, _acc = _acc
        };
        Array.Copy(P, r.P, Points);
        Array.Copy(Prev, r.Prev, Points);
        return r;
    }
}
