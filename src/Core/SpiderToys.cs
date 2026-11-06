namespace SpiderBuddy.Core;

public enum ToyKind { None, Laser, Ball, Feather, Bell, Bug }

public readonly struct ToyInfo
{
    public readonly double Radius, Restitution, Mass, EdgeDrag, Brake, GravityShare, AirDrag;
    public readonly bool Rolls;
    public readonly double Tether, Lure, LoftMin, LoftMax;
    public ToyInfo(double radius, double restitution, double mass, double edgeDrag, double brake,
        double gravityShare, double airDrag, bool rolls, double tether, double lure, double loftMin, double loftMax)
    {
        Radius = radius; Restitution = restitution; Mass = mass; EdgeDrag = edgeDrag; Brake = brake;
        GravityShare = gravityShare; AirDrag = airDrag; Rolls = rolls; Tether = tether; Lure = lure;
        LoftMin = loftMin; LoftMax = loftMax;
    }
}

public static class ToyTable
{
    /// <summary>The exact Stage 11.2 numbers: one body, five sets of numbers.</summary>
    public static ToyInfo For(ToyKind k) => k switch
    {
        ToyKind.Ball => new(7, 0.72, 1, 0.6, 30, 1, 0.12, true, 0, 1.0, 0.15, 0.7),
        ToyKind.Feather => new(9, 0.05, 0.35, 6, 220, 0.09, 2.6, false, 105, 1.15, 0.9, 1.3),
        ToyKind.Bell => new(6.5, 0.42, 1.7, 0.9, 40, 1, 0.12, true, 0, 0.9, 0.05, 0.35),
        ToyKind.Bug => new(7.5, 0.22, 1.3, 4, 160, 1, 0.12, false, 0, 1.1, 0, 0.15),
        _ => new(3, 0.1, 0.1, 0, 0, 0, 0, false, 0, 0, 0, 0),
    };
}

public sealed class Toy
{
    public ToyKind Kind;
    public V2 Pos, Vel;
    public double Roll, Spin, Wound, Age, LastSound = -99;
    public int Knocks;
    public bool Held, OnSurface;
    public V2 Dir = new(1, 0);
    public double Scale = 1;
    public ToyInfo Info => ToyTable.For(Kind);
}

/// <summary>Stage 11 — toys and the laser (spec 11).</summary>
public sealed partial class Spider
{
    public readonly List<Toy> Toys = new();
    public ToyKind HandToy { get; private set; }
    public Toy? HandObject { get; private set; }
    public bool ToySounds = true;
    public int ToyPats;
    public double ToyPuzzledUntil = -1;
    public string? FavouriteToy;
    public bool ToyCatchesPointer => HandToy != ToyKind.None;
    public V2 LaserPos => Cursor;

    public event Action<ToyKind>? ToySound;
    public event Action<ToyKind>? ToyPicked;

    double _lastPat = -99;

    public Toy? NearestToy(double within)
    {
        Toy? best = null;
        double bestD = double.MaxValue;
        foreach (var t in Toys)
        {
            if (t.Held) continue;
            double d = t.Pos.DistanceTo(Pos);
            if (d < within && d < bestD) { bestD = d; best = t; }
        }
        return best;
    }

    /// <summary>Pick a toy up into the hand; only one rides the pointer at a time (spec 11.1).</summary>
    public bool PickToy(ToyKind kind)
    {
        if (kind == ToyKind.None) { PutAwayToy(); return true; }
        if (HandToy != ToyKind.None) PutAwayToy();
        HandToy = kind;
        if (kind != ToyKind.Laser)
        {
            HandObject = new Toy { Kind = kind, Pos = Cursor, Held = true, Scale = Scale };
            if (kind == ToyKind.Feather) HandObject.Pos = Cursor + new V2(0, -ToyTable.For(kind).Tether * Scale);
        }
        ToyPicked?.Invoke(kind);
        return true;
    }

    /// <summary>Right-click or Esc while carrying: the toy goes away (spec 11.1).</summary>
    public void PutAwayToy()
    {
        if (HandToy == ToyKind.Laser)
        {
            ToyPuzzledUntil = Time + 4;
            ShowEmote(PointerEmote.Question, 2.5);
        }
        HandObject = null;
        HandToy = ToyKind.None;
    }

    public void PutAwayToy(Toy t)
    {
        Toys.Remove(t);
        if (HandObject == t) { HandObject = null; HandToy = ToyKind.None; }
    }

    /// <summary>Click: put the carried toy down at the pointer.</summary>
    public Toy? PlaceToy()
    {
        if (HandObject is not { } t) return null;
        HandObject = null;
        HandToy = ToyKind.None;
        t.Held = false;
        t.Pos = Cursor;
        var spot = Map.NearestSpot(t.Pos, t.Info.Radius + 10, null, Scale);
        if (spot is { } s && SurfaceUp(s)) { t.Pos = s.Point; t.OnSurface = true; }
        if (t.Kind == ToyKind.Bug) t.Wound = 8;
        Toys.Add(t);
        return t;
    }

    public Toy AddToy(ToyKind kind, V2 pos, V2? velocity = null)
    {
        var t = new Toy { Kind = kind, Pos = pos, Vel = velocity ?? V2.Zero, Scale = Scale };
        var spot = Map.NearestSpot(pos, t.Info.Radius + 10, null, Scale);
        if (spot is { } s && SurfaceUp(s)) { t.Pos = s.Point; t.OnSurface = true; }
        Toys.Add(t);
        return t;
    }

    public bool PickUpToy(Toy t)
    {
        if (!Toys.Remove(t)) return false;
        HandObject = t;
        HandToy = t.Kind;
        t.Held = true;
        t.Pos = Cursor;
        t.Vel = V2.Zero;
        return true;
    }

    /// <summary>Drag + flick throws a toy; the throw speed is clamped like the spider's (spec 11.1).</summary>
    public void ThrowToy(Toy t, V2 velocity)
    {
        double len = velocity.Length;
        if (len > MaxThrowSpeed) velocity *= MaxThrowSpeed / len;
        t.Held = false;
        t.OnSurface = false;
        t.Vel = velocity;
        t.Pos = Cursor;
    }

    public bool BatToy(Toy t)
    {
        if (Mode != Mode.Attached || t.Held) return false;
        var info = t.Info;
        double loft = Rng.Range(info.LoftMin, info.LoftMax);
        V2 dir = t.Pos.X >= Pos.X ? new V2(1, 0) : new V2(-1, 0);
        double speed = 280 * Scale;
        t.Vel = dir * (speed * Math.Cos(loft)) + new V2(0, speed * Math.Sin(loft));
        t.OnSurface = false;
        t.Knocks++;
        Ring(t);
        Play(Activity.Pounce, 0.35);
        Happy.Velocity = 5;
        ToyPats++;
        FavouriteToy = $"toy.{t.Kind}";
        PointerRemembered?.Invoke(PointerMemoryEvent.Played);
        return true;
    }

    public void PokeToy(Toy t)
    {
        t.Vel += new V2(Facing * 130 * Scale, 90 * Scale);
        t.OnSurface = false;
        t.Knocks++;
        Ring(t);
    }

    /// <summary>Offered from think(): a toy left lying about gets batted now and then (spec 11.3).</summary>
    public bool MaybePlayWithToy()
    {
        if (HandToy != ToyKind.None || Mode != Mode.Attached) return false;
        var t = NearestToy(260 * Scale);
        if (t is null) return false;
        if (!Rng.Chance(0.2 + 0.55 * Design.Personality.Playfulness)) return false;
        return BatToy(t);
    }

    void Ring(Toy t)
    {
        if (!ToySounds) return;
        if (Time - t.LastSound < 0.08) return;
        t.LastSound = Time;
        ToySound?.Invoke(t.Kind);
    }

    bool SurfaceUp(Spot s)
    {
        var seg = Map.Loop(s.LoopId)?.SegAt(s.SegIdx);
        return seg is { } sg && sg.Normal.Y > 0.5;
    }

    bool SurfaceFlat(Spot s)
    {
        var seg = Map.Loop(s.LoopId)?.SegAt(s.SegIdx);
        return seg is { } sg && sg.Normal.Y > 0.999;
    }

    /// <summary>Toys ride the pointer; a feather trails from it on its string (spec 11.1).</summary>
    void UpdateToys(double dt)
    {
        if (HandObject is { } hand)
        {
            var info = hand.Info;
            if (hand.Kind == ToyKind.Feather)
            {
                hand.Pos += hand.Vel * dt;
                hand.Vel += new V2(0, -1950 * info.GravityShare) * dt;
                hand.Vel *= Math.Exp(-info.AirDrag * dt);
                V2 to = hand.Pos - Cursor;
                double max = info.Tether * Scale;
                if (to.Length > max) { hand.Pos = Cursor + to.Normalized * max; hand.Vel *= 0.2; }
                hand.Spin = Math.Sin(Time * 3.4) * 0.35;
            }
            else hand.Pos = Cursor;
        }

        if (HandToy == ToyKind.Laser) UpdateLaser(dt);

        for (int i = Toys.Count - 1; i >= 0; i--)
        {
            var t = Toys[i];
            if (t.Held) continue;
            t.Age += dt;
            UpdateToy(t, dt);
        }
    }

    void UpdateLaser(double dt)
    {
        if (Cinema) return;
        if (Mode != Mode.Attached || PreyHunt != HuntStage.None || InHammock) return;
        double d = Pos.DistanceTo(Cursor);
        if (d > 45 * Scale)
        {
            MoveTowardPoint(Cursor, 155 * Scale, dt);
            Play(Activity.Scurry, 0.4);
        }
        else if (Time - _lastPat > 0.3)
        {
            _lastPat = Time;
            ToyPats++;
            Play(Activity.Pounce, 0.3);
            Happy.Velocity = 4;
            PointerRemembered?.Invoke(PointerMemoryEvent.Played);
        }
    }

    void UpdateToy(Toy t, double dt)
    {
        var info = t.Info;

        if (t.OnSurface)
        {
            var spot = Map.NearestSpot(t.Pos, info.Radius + 24 * Scale, null, Scale);
            if (spot is { } s && SurfaceUp(s) && (!info.Rolls || SurfaceFlat(s)))
            {
                t.Pos = s.Point;
                if (t.Kind == ToyKind.Bug && t.Wound > 0)
                {
                    t.Wound = Math.Max(0, t.Wound - dt);
                    V2 want = t.Pos + new V2(t.Dir.X * 55 * Scale * dt, 0);
                    var next = Map.NearestSpot(want, info.Radius + 14, null, Scale);
                    if (next is { } ns && SurfaceUp(ns)) t.Pos = ns.Point;
                    else t.Dir = new V2(-t.Dir.X, 0);
                }
                if (info.Rolls) RollOnSurface(t, s, info, dt);
                else { t.Vel = V2.Zero; t.Roll = 0; }
                return;
            }
            t.OnSurface = false;
        }

        t.Vel += new V2(0, -1950 * info.GravityShare) * dt;
        t.Vel *= Math.Exp(-info.AirDrag * dt);
        t.Pos += t.Vel * dt;
        BounceScreens(t, info);

        var hit = Map.NearestSpot(t.Pos, info.Radius + 8, null, Scale);
        if (hit is { } h && SurfaceUp(h) && (!info.Rolls || SurfaceFlat(h)))
        {
            var seg = Map.Loop(h.LoopId)?.SegAt(h.SegIdx);
            if (seg is { } sg)
            {
                double vn = t.Vel.Dot(sg.Normal);
                if (vn < 0)
                {
                    t.Pos = h.Point + sg.Normal * (info.Radius + 0.5);
                    if (Math.Abs(vn) > 30)
                    {
                        t.Vel -= sg.Normal * (1 + info.Restitution) * vn;
                        t.Knocks++;
                        if (t.Kind == ToyKind.Bell) Ring(t);
                    }
                    else
                    {
                        t.Vel = new V2(t.Vel.X, 0);
                        t.Pos = h.Point;
                        t.OnSurface = true;
                    }
                }
            }
        }
    }

    void RollOnSurface(Toy t, Spot s, ToyInfo info, double dt)
    {
        var seg = Map.Loop(s.LoopId)?.SegAt(s.SegIdx);
        if (seg is not { } sg) return;
        V2 tangent = (sg.B - sg.A).Normalized;
        double roll = t.Vel.Dot(tangent);
        roll *= Math.Exp(-info.EdgeDrag * dt);
        double brake = info.Brake * dt;
        roll = roll > 0 ? Math.Max(0, roll - brake) : Math.Min(0, roll + brake);
        t.Roll = roll;
        t.Vel = tangent * roll;
        t.Spin += roll * dt / Math.Max(1, info.Radius);
        t.Pos = s.Point + tangent * (roll * dt);
        var (u, _) = M.ProjectOnSegment(t.Pos, sg.A, sg.B);
        if (u <= 0.03 || u >= 0.97)
        {
            // Roll cleanly off the end: beyond the lip, or it would be recaught by the same edge.
            t.Pos += tangent * (info.Radius + 20) + new V2(0, -(info.Radius + 24));
            t.OnSurface = false;
            return;
        }
        var next = Map.NearestSpot(t.Pos, info.Radius + 24 * Scale, null, Scale);
        if (next is not { } n || !SurfaceUp(n)) t.OnSurface = false;
    }

    void BounceScreens(Toy t, ToyInfo info)
    {
        var r = Map.WorldBounds;
        if (!r.IsValid || r.W <= 0 || r.H <= 0) return;
        if (t.Pos.X < r.MinX) { t.Pos = new V2(r.MinX, t.Pos.Y); t.Vel = new V2(-t.Vel.X * info.Restitution, t.Vel.Y); }
        else if (t.Pos.X > r.MaxX) { t.Pos = new V2(r.MaxX, t.Pos.Y); t.Vel = new V2(-t.Vel.X * info.Restitution, t.Vel.Y); }
        if (t.Pos.Y < r.MinY) { t.Pos = new V2(t.Pos.X, r.MinY); t.Vel = new V2(t.Vel.X, -t.Vel.Y * info.Restitution); }
        else if (t.Pos.Y > r.MaxY) { t.Pos = new V2(t.Pos.X, r.MaxY); t.Vel = new V2(t.Vel.X, -t.Vel.Y * info.Restitution); }
    }
}
