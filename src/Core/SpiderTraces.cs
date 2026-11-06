namespace SpiderBuddy.Core;

public enum TraceKind { Strand, Web, Leftover }

public sealed class Trace
{
    public TraceKind Kind;
    public V2 A, B, Pos, Vel;
    public string? LoopA, LoopB;
    public Rect RectA, RectB;
    public bool PinnedA, PinnedB, OnSurface;
    public double Length, Age, Life = 180, Alpha = 1, Spin;
    public int Knocks;
    public PreyKind Prey;
    public readonly List<(V2 A, V2 B)> Threads = new();
}

/// <summary>Stage 12 — what the spider leaves about, and how it fades (spec 12).</summary>
public sealed partial class Spider
{
    public readonly List<Trace> Traces = new();
    public int TraceLimit = 24;
    public bool TraceUnlimited;
    public bool InBox;
    public double TraceLeapChance = 0.35;
    public double TraceSwingChance = 0.6;

    bool _leaveTraces;
    public bool LeaveTraces
    {
        get => _leaveTraces;
        set
        {
            _leaveTraces = value;
            // Turning it off clears whatever is out (spec 12.2).
            if (!value) Traces.Clear();
        }
    }

    public void SetTraceLimit(int v)
    {
        TraceUnlimited = v >= 60;
        TraceLimit = TraceUnlimited ? 60 : Math.Max(3, Math.Min(60, v));
        TrimTraces();
    }

    public void TidyTraces() => Traces.Clear();

    void TrimTraces()
    {
        if (TraceUnlimited) return;
        while (Traces.Count > TraceLimit) Traces.RemoveAt(0);
    }

    public Trace? AddStrand(V2 a, V2 b, string? loopA = null, string? loopB = null)
    {
        if (!CanLeaveTrace()) return null;
        var t = new Trace
        {
            Kind = TraceKind.Strand, A = a, B = b,
            Length = Math.Max(1, a.DistanceTo(b)), Life = 180
        };
        if (loopA is null)
        {
            var sa = Map.NearestSpot(a, 28 * Scale, null, Scale);
            if (sa is { } pa)
            {
                loopA = pa.LoopId;
                t.RectA = Map.Loop(pa.LoopId)?.Rect ?? Rect.Zero;
            }
        }
        if (loopB is null)
        {
            var sb = Map.NearestSpot(b, 28 * Scale, null, Scale);
            if (sb is { } pb)
            {
                loopB = pb.LoopId;
                t.RectB = Map.Loop(pb.LoopId)?.Rect ?? Rect.Zero;
            }
        }
        t.LoopA = loopA;
        t.LoopB = loopB;
        t.PinnedA = loopA is not null;
        t.PinnedB = loopB is not null;
        if (t.LoopA is { } la && t.RectA.IsValid) t.RectA = Map.Loop(la)?.Rect ?? t.RectA;
        if (t.LoopB is { } lb && t.RectB.IsValid) t.RectB = Map.Loop(lb)?.Rect ?? t.RectB;
        Traces.Add(t);
        TrimTraces();
        return t;
    }

    public Trace? AddWeb(V2 site)
    {
        if (!CanLeaveTrace()) return null;
        var t = new Trace { Kind = TraceKind.Web, Pos = site, A = site, B = site, Life = 240 };
        int threads = 22;
        for (int i = 0; i < threads; i++)
        {
            double ang = i * 2.39996;
            double r = 5 + (i % 5) * 4.2;
            V2 end = site + new V2(Math.Cos(ang) * r, Math.Sin(ang) * r);
            t.Threads.Add((site, end));
        }
        Traces.Add(t);
        TrimTraces();
        return t;
    }

    public Trace? AddLeftovers(Prey p)
    {
        if (!CanLeaveTrace()) return null;
        if (p.Kind is not (PreyKind.FruitFly or PreyKind.Moth or PreyKind.Beetle)) return null;
        var t = new Trace
        {
            Kind = TraceKind.Leftover, Pos = p.Pos, OnSurface = p.OnSurface,
            Prey = p.Kind, Life = 120, Spin = Rng.Range(-0.5, 0.5)
        };
        Traces.Add(t);
        TrimTraces();
        return t;
    }

    bool CanLeaveTrace() => LeaveTraces && !InBox && WebsEnabled;

    /// <summary>Pointer brush: a slow push moves a strand, a fast swipe tears it (spec 12.1).</summary>
    public void FlickTrace(V2 at, double speed)
    {
        for (int i = Traces.Count - 1; i >= 0; i--)
        {
            var t = Traces[i];
            V2 centre = t.Kind == TraceKind.Strand ? (t.A + t.B) * 0.5 : t.Pos;
            if (centre.DistanceTo(at) > 45 * Scale) continue;
            if (speed > 420) Traces.RemoveAt(i);
            else { t.A += new V2(speed * 0.01, 0); t.B += new V2(speed * 0.006, 0); }
        }
    }

    void UpdateTraces(double dt)
    {
        if (!LeaveTraces) return;
        for (int i = Traces.Count - 1; i >= 0; i--)
        {
            var t = Traces[i];
            t.Age += dt;
            t.Alpha = 1 - t.Age / Math.Max(0.1, t.Life);
            if (t.Alpha <= 0) { Traces.RemoveAt(i); continue; }

            if (t.Kind == TraceKind.Strand)
            {
                if (t.PinnedA)
                {
                    var l = t.LoopA is null ? null : Map.Loop(t.LoopA);
                    if (l is null) { Traces.RemoveAt(i); continue; }
                    t.A += l.Rect.Mid - t.RectA.Mid;
                    t.RectA = l.Rect;
                }
                if (t.PinnedB)
                {
                    var l = t.LoopB is null ? null : Map.Loop(t.LoopB);
                    if (l is null) { Traces.RemoveAt(i); continue; }
                    t.B += l.Rect.Mid - t.RectB.Mid;
                    t.RectB = l.Rect;
                }
                if (t.PinnedA && t.PinnedB && t.A.DistanceTo(t.B) > t.Length * 2.2)
                    Traces.RemoveAt(i);
            }
            else if (t.Kind == TraceKind.Leftover)
            {
                if (!t.OnSurface)
                {
                    t.Vel += new V2(0, -1950 * 0.6) * dt;
                    t.Pos += t.Vel * dt;
                    var land = Map.NearestSpot(t.Pos, 18 * Scale, null, Scale);
                    if (land is { } s && t.Vel.Y < 0)
                    {
                        t.Pos = s.Point;
                        t.OnSurface = true;
                        t.Vel = V2.Zero;
                    }
                }
                if (t.OnSurface && Pos.DistanceTo(t.Pos) < 18 * Scale && Math.Abs(Speed) > 18)
                {
                    t.Vel = new V2(Facing * 90, 100);
                    t.OnSurface = false;
                    t.Knocks++;
                }
                t.Spin += t.Vel.X * dt * 0.01;
            }
        }
    }
}
