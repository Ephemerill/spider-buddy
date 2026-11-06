namespace SpiderBuddy.Core;

public enum PreyKind { Cricket, Worm, FruitFly, Moth, Beetle, Ant, Mosquito, Ladybug }
public enum PreyState { Loose, Caught, Eaten, Squashed }
public enum HuntStage { None, Watch, Approach, Stalk, Ambush, Pounce, Carry, Eat }

public readonly struct PreyInfo
{
    public readonly bool Flies, Climbs, TakesOff, Armoured, Bitter;
    public readonly double CatchRadius, MealTime, Nourishment, Clearance, Wariness;
    public PreyInfo(bool flies, bool climbs, bool takesOff, bool armoured, bool bitter,
        double catchRadius, double mealTime, double nourishment, double clearance, double wariness)
    {
        Flies = flies; Climbs = climbs; TakesOff = takesOff; Armoured = armoured; Bitter = bitter;
        CatchRadius = catchRadius; MealTime = mealTime; Nourishment = nourishment;
        Clearance = clearance; Wariness = wariness;
    }
}

public sealed class Prey
{
    public PreyKind Kind;
    public int Id;
    public double Scale = 1;
    public V2 Pos, Vel;
    public double Heading, Facing = 1;
    public PreyState State = PreyState.Loose;
    public bool Noticed, Spurned, OnSurface, Held, Shelled;
    public double Eaten01, Timer, Age, Fear, LeaveAfter;
    public int Knocks;

    public static PreyInfo Info(PreyKind k) => k switch
    {
        PreyKind.Cricket => new(false, false, false, false, false, 22, 5.5, 0.55, 4, 1),
        PreyKind.Worm => new(false, false, false, false, false, 24, 6.5, 0.60, 2.5, 1),
        PreyKind.FruitFly => new(true, false, false, false, false, 20, 3.2, 0.30, 3, 1),
        PreyKind.Moth => new(true, false, false, false, false, 26, 5.0, 0.50, 2.5, 0.45),
        PreyKind.Beetle => new(false, false, true, true, false, 22, 7.5, 0.70, 3, 1),
        PreyKind.Ant => new(false, true, false, false, false, 17, 2.4, 0.25, 2.5, 1),
        PreyKind.Mosquito => new(true, false, false, false, false, 17, 2.2, 0.25, 4.5, 1.5),
        _ => new(false, true, true, false, true, 19, 1.4, 0.00, 2.5, 0.6),
    };

    public double NoticeReach => 75 * Scale * (1 + 0.6);

    /// <summary>Wildlife odds by kind (spec 10.5).</summary>
    public static PreyKind WanderingIn(bool night, bool raining, Rng rng)
    {
        var w = new double[8];
        w[(int)PreyKind.FruitFly] = 3;
        w[(int)PreyKind.Ant] = 2.5;
        w[(int)PreyKind.Beetle] = 1.3;
        w[(int)PreyKind.Moth] = night ? 5 : 0.7;
        w[(int)PreyKind.Mosquito] = night ? 2.5 : 1;
        w[(int)PreyKind.Ladybug] = night ? 0.2 : 1.8;
        w[(int)PreyKind.Cricket] = night ? 2 : 0.8;
        w[(int)PreyKind.Worm] = raining ? 5 : 0.3;
        return (PreyKind)rng.WeightedIndex(w);
    }
}

/// <summary>Stage 10 — prey, the hunt and feeding (spec 10).</summary>
public sealed partial class Spider
{
    public readonly List<Prey> PreyItems = new();
    public Prey? Quarry;
    public HuntStage PreyHunt;
    public string? HuntTag;
    public double Prowess = 0.5;
    public double Fed;
    public double HuntTimer;
    public double EatTimer;
    public bool LearnedBitter;
    public V2? PounceMark;
    public bool Night, Raining, InHabitat, Fullscreen;
    public double UserIdleFor, IdleLimit = 300;

    public bool WildlifeEnabled;
    public double WildlifeFrequency = 5400;
    public double WildlifeIn = 5400;

    int _preyId;

    public int LoosePrey => PreyItems.Count(p => p.State == PreyState.Loose);

    /// <summary>Release one creature: walkers onto a ledge a little way off, fliers into the air (spec 10.4).</summary>
    public Prey? ReleasePrey(PreyKind kind, V2? at = null)
    {
        if (Box is { } box)
        {
            at ??= box.Mid;
            if (at is { } mark && !box.Contains(mark)) at = box.Mid;
        }
        if (LoosePrey >= 4) return null;
        var info = Prey.Info(kind);
        var p = new Prey { Kind = kind, Id = ++_preyId, Scale = Scale, Age = 0 };
        if (info.Flies)
        {
            p.Pos = at ?? Pos + new V2(Rng.Range(-120, 120) * Scale, Rng.Range(60, 160) * Scale);
            p.Vel = at is null ? new V2(Rng.Range(-20, 20), Rng.Range(-10, 10)) : V2.Zero;
            p.OnSurface = false;
            p.Timer = Rng.Range(0.4, 1.2);
        }
        else
        {
            var spot = at is { } mark
                ? Map.NearestSpot(mark, 360 * Scale, null, Scale) ?? Map.NearestSpot(Pos, 80 * Scale, null, Scale)
                : Map.NearestSpot(Pos + new V2(Rng.Chance(0.5) ? 180 * Scale : -180 * Scale, 0), 320 * Scale, null, Scale)
                  ?? Map.NearestSpot(Pos, 80 * Scale, null, Scale);
            p.Pos = spot?.Point ?? at ?? Pos;
            p.OnSurface = spot is not null;
            p.Heading = Rng.Range(-M.Pi, M.Pi);
            p.Timer = Rng.Range(0.6, 1.8);
        }
        PreyItems.Add(p);
        return p;
    }

    /// <summary>A wild arrival (spec 10.5): fliers at the screen side, walkers from a crack, ants in a line.</summary>
    public List<Prey> ReleaseWildlife(PreyKind? kind = null)
    {
        var born = new List<Prey>();
        var k = kind ?? Prey.WanderingIn(Night, Raining, Rng);
        var r = Map.WorldBounds;
        bool air = Prey.Info(k).Flies || k is PreyKind.Beetle or PreyKind.Ladybug;
        V2 at = air
            ? new V2(Rng.Chance(0.5) ? r.MinX + 6 : r.MaxX - 6, r.Y + r.H * Rng.Range(0.35, 0.7))
            : new V2(r.MinX + 24, r.MinY + 8);
        int n = k == PreyKind.Ant ? Rng.RangeInt(3, 6) : 1;
        for (int i = 0; i < n; i++)
        {
            var p = ReleasePrey(k, at + new V2(i * 16 * Scale, air ? 0 : i * 2));
            if (p is null) break;
            p.LeaveAfter = Rng.Range(180, 300);
            born.Add(p);
        }
        return born;
    }

    public void ClearPrey() => PreyItems.Clear();

    /// <summary>One frame for every creature, and whatever the spider is doing about it.</summary>
    void UpdatePrey(double dt)
    {
        for (int i = PreyItems.Count - 1; i >= 0; i--)
        {
            var p = PreyItems[i];
            if (p.State == PreyState.Loose && p.LeaveAfter > 0 && p.Age > p.LeaveAfter)
            {
                // Uncaught wildlife eventually slips away or flies off (spec 10.5).
                if (Quarry == p) AbandonHunt();
                PreyItems.RemoveAt(i);
                continue;
            }
            UpdateOnePrey(p, dt);
        }
        UpdateHunt(dt);
    }

    void UpdateOnePrey(Prey p, double dt)
    {
        if (p.State == PreyState.Eaten || p.State == PreyState.Squashed) return;
        p.Age += dt;
        p.Timer -= dt;
        p.Fear = Math.Max(0, p.Fear - dt);

        if (p.State == PreyState.Caught)
        {
            p.Held = true;
            p.Pos = Pos + new V2(Facing * 8 * Scale, -4 * Scale);
            if (EatTimer > 0)
            {
                EatTimer -= dt;
                p.Eaten01 = M.Clamp01(1 - EatTimer / Math.Max(0.1, Prey.Info(p.Kind).MealTime));
                if (EatTimer <= 0) FinishMeal(p);
            }
            return;
        }

        double d = p.Pos.DistanceTo(Pos);
        double notice = p.Kind == PreyKind.Moth ? p.NoticeReach * 0.5 : p.NoticeReach;
        if (!p.Noticed && d < notice && (Speed > 60 || d < notice * 0.4)) p.Noticed = true;

        switch (p.Kind)
        {
            case PreyKind.Cricket:
                if (d < 90 * Scale && p.Timer <= 0)
                {
                    if (Rng.Chance(0.5)) { p.Timer = 0.8; }
                    else
                    {
                        V2 away = (p.Pos - Pos).Normalized;
                        p.Vel = away * 55 + new V2(0, 150);
                        p.OnSurface = false;
                        p.Timer = Rng.Range(0.9, 1.6);
                    }
                }
                StepSurface(p, dt, 0, 4);
                break;

            case PreyKind.Worm:
                StepSurface(p, dt, d < 150 * Scale ? 14 : 7, 2);
                break;

            case PreyKind.FruitFly:
                if (p.OnSurface && d < 70 * Scale) { p.OnSurface = false; p.Vel = new V2(Rng.Range(-60, 60), 90); }
                if (!p.OnSurface)
                {
                    if (p.Timer <= 0) { p.Timer = Rng.Range(0.3, 0.8); p.Vel = new V2(Rng.Range(-70, 70), Rng.Range(-40, 40)); }
                    p.Vel *= Math.Exp(-1.5 * dt);
                    p.Pos += p.Vel * dt;
                    if (Map.NearestSpot(p.Pos, 14 * Scale, null, Scale) is { } perch && p.Vel.Length < 30)
                    {
                        p.Pos = perch.Point; p.OnSurface = true;
                    }
                }
                break;

            case PreyKind.Moth:
                if (p.Age < 18 && Cursor.DistanceTo(p.Pos) < 420 * Scale)
                {
                    V2 to = Cursor - p.Pos;
                    double orbit = Math.Sin(p.Age * 2.4) * 40;
                    p.Vel = to.Normalized * 38 + new V2(-to.Y, to.X).Normalized * orbit;
                    p.Pos += p.Vel * dt;
                    p.OnSurface = false;
                }
                else if (p.OnSurface)
                {
                    // Wings folded back like a roof: rest a long while.
                    p.Vel *= Math.Exp(-4 * dt);
                }
                else
                {
                    if (Map.NearestSpot(p.Pos, 30 * Scale, null, Scale) is { } rest) { p.Pos = rest.Point; p.OnSurface = true; }
                    else { p.Pos += new V2(0, -18 * dt); }
                }
                break;

            case PreyKind.Beetle:
                if (p.Shelled && p.Timer <= 0 && Speed < 8) { p.Shelled = false; p.Fear = 3.5; }
                if (d < 80 * Scale && !p.Shelled && p.Fear <= 0) { p.Shelled = true; p.Timer = 3.5; }
                StepSurface(p, dt, p.Shelled ? 0 : 12, 1);
                break;

            case PreyKind.Ant:
                // It feels something big *walking* and turns tail; a still spider is furniture.
                StepSurface(p, dt, 55, Speed > 20 && d < 60 * Scale ? (p.Pos.X >= Pos.X ? 1 : -1) : 0);
                break;

            case PreyKind.Mosquito:
                if (p.Timer <= 0)
                {
                    p.Timer = Rng.Range(1.6, 2.8);
                    p.Vel = Rng.Chance(0.5) ? new V2(Rng.Range(-180, 180), Rng.Range(-80, 80))
                        : new V2(Math.Sin(p.Age * 9) * 12, Math.Cos(p.Age * 7) * 12);
                }
                p.Pos += p.Vel * dt;
                p.Vel *= Math.Exp(-0.6 * dt);
                break;

            case PreyKind.Ladybug:
                if (d < 70 * Scale && !p.OnSurface)
                {
                    p.Vel = new V2((p.Pos.X >= Pos.X ? 1 : -1) * 90, 140);
                }
                if (d < 70 * Scale && p.OnSurface)
                {
                    p.OnSurface = false;
                    p.Vel = new V2((p.Pos.X >= Pos.X ? 1 : -1) * 80, 130);
                }
                if (!p.OnSurface)
                {
                    p.Vel += new V2(0, -260) * dt;
                    p.Pos += p.Vel * dt;
                    if (Map.NearestSpot(p.Pos, 16 * Scale, null, Scale) is { } land && p.Vel.Y < 0)
                    { p.Pos = land.Point; p.OnSurface = true; p.Vel = V2.Zero; }
                }
                else StepSurface(p, dt, 15, 0);   // always climbing upward
                break;
        }

        if ((p.Kind is PreyKind.Cricket or PreyKind.Worm or PreyKind.FruitFly) && !p.OnSurface && p.Vel.Y != 0)
            Fall(p, dt);
    }

    void Fall(Prey p, double dt)
    {
        p.Vel += new V2(0, -900) * dt;
        p.Pos += p.Vel * dt;
        if (Map.NearestSpot(p.Pos, 12 * Scale, null, Scale) is { } land && p.Vel.Y < 0)
        {
            p.Pos = land.Point; p.OnSurface = true; p.Vel = V2.Zero;
        }
    }

    void StepSurface(Prey p, double dt, double speed, int turn)
    {
        if (!p.OnSurface) { Fall(p, dt); return; }
        if (p.Timer <= 0) { p.Timer = Rng.Range(0.8, 2.0); p.Heading = Rng.Range(-M.Pi, M.Pi); }
        if (speed <= 0.01) return;
        V2 dir = new(Math.Cos(p.Heading), Math.Sin(p.Heading));
        if (turn != 0) dir = new V2(turn, Math.Abs(dir.Y) * 0.3);
        if (p.Kind == PreyKind.Ladybug) dir = new V2(dir.X * 0.2, 1);
        var spot = Map.NearestSpot(p.Pos + dir * speed * dt, 30 * Scale, null, Scale);
        if (spot is { } s)
        {
            p.Pos = s.Point;
            p.Facing = dir.X >= 0 ? 1 : -1;
            p.Heading = dir.Angle;
        }
        else p.OnSurface = false;
    }

    // ------------------------------------------------------------------ the hunt (10.3)

    public Prey? FindQuarry()
    {
        Prey? best = null;
        double bestD = double.MaxValue;
        foreach (var p in PreyItems)
        {
            if (p.State != PreyState.Loose || p.Spurned || !p.Noticed) continue;
            double d = p.Pos.DistanceTo(Pos);
            if (d < bestD) { bestD = d; best = p; }
        }
        return best;
    }

    public bool StartHunt(Prey p)
    {
        if (Cinema) return false;
        if (p.State != PreyState.Loose) return false;
        Quarry = p;
        PreyHunt = HuntStage.Watch;
        HuntTimer = 0.6;
        HuntTag = p.Kind.ToString();
        TurnTo(p.Pos.X >= Pos.X ? 1 : -1);
        Play(Activity.Watch, 0.6);
        return true;
    }

    void UpdateHunt(double dt)
    {
        if (Quarry is not { } q || q.State != PreyState.Loose)
        {
            if (PreyHunt == HuntStage.Carry) UpdateCarry(dt);
            else if (Quarry is not null && Quarry.State != PreyState.Caught)
            {
                Prowess = Math.Max(0, Prowess - 0.01);
                Quarry = null;
                if (PreyHunt is HuntStage.Watch or HuntStage.Approach or HuntStage.Stalk or HuntStage.Pounce)
                    PreyHunt = HuntStage.None;
            }
            return;
        }

        HuntTimer -= dt;
        if (PreyHunt == HuntStage.Watch)
        {
            TurnTo(q.Pos.X >= Pos.X ? 1 : -1);
            if (HuntTimer <= 0) { PreyHunt = HuntStage.Approach; Play(Activity.Walk, 3); }
            return;
        }
        if (PreyHunt == HuntStage.Approach)
        {
            MoveTowardPrey(q, (q.Kind == PreyKind.Beetle ? 55 : 90) * Scale, dt);
            if (q.Pos.DistanceTo(Pos) < 110 * Scale) { PreyHunt = HuntStage.Stalk; HuntTimer = 1.2; Play(Activity.Sneak, 1.2); }
            if (q.Pos.DistanceTo(Pos) > 520 * Scale) AbandonHunt();
            return;
        }
        if (PreyHunt == HuntStage.Stalk)
        {
            if (q.Kind == PreyKind.Ant)
            {
                // Lie in wait in its path instead of chasing a tireless climber (spec 10.2).
                V2 dir = new(Math.Cos(q.Heading), Math.Sin(q.Heading));
                V2 rel = Pos - q.Pos;
                double along = rel.Dot(dir);
                double perp = Math.Abs(rel.X * dir.Y - rel.Y * dir.X);
                if (along > -10 * Scale && perp < 26 * Scale)
                {
                    // Already standing where it is heading: just wait.
                    PreyHunt = HuntStage.Ambush;
                    HuntTimer = 8;
                    Play(Activity.Crouch, 8);
                }
                else
                {
                    V2 ahead = q.Pos + dir * 60 * Scale;
                    if (Pos.DistanceTo(ahead) > 24 * Scale) MoveTowardPoint(ahead, 95 * Scale, dt);
                    else { PreyHunt = HuntStage.Ambush; HuntTimer = 8; Play(Activity.Crouch, 8); }
                }
                if (q.Pos.DistanceTo(Pos) > 220 * Scale) { PreyHunt = HuntStage.Approach; HuntTimer = 1; }
                return;
            }
            MoveTowardPrey(q, (q.Kind == PreyKind.Beetle ? 20 : 32) * Scale, dt);
            TurnTo(q.Pos.X >= Pos.X ? 1 : -1);
            if (HuntTimer <= 0 || q.Pos.DistanceTo(Pos) < 55 * Scale)
            {
                PreyHunt = HuntStage.Pounce;
                HuntTimer = 0.45;
                Play(Activity.Crouch, 0.45);
                PounceMark = q.Pos;
            }
            return;
        }
        if (PreyHunt == HuntStage.Pounce)
        {
            if (q.Kind == PreyKind.Beetle)
            {
                if (q.Shelled)
                {
                    // Keep quite still beside it until it comes out (spec 10.2).
                    Play(Activity.Watch, 0.5);
                    if (HuntTimer < -12) AbandonHunt();
                    return;
                }
                if (TryCatch(q)) return;
                if (Mode == Mode.Attached && q.Pos.DistanceTo(Pos) > 24 * Scale)
                    MoveTowardPrey(q, 25 * Scale, dt);
                if (HuntTimer < -12) AbandonHunt();
                return;
            }
            if (TryCatch(q)) return;
            if (Mode == Mode.Attached)
            {
                double dist = q.Pos.DistanceTo(Pos);
                // Re-aim through the crouch at where a falling/moving quarry will be.
                if (HuntTimer > 0 && q.Pos.Y < Pos.Y - 4 && q.Vel.Length > 3)
                {
                    double fall = Pos.Y - q.Pos.Y;
                    double flight = (-90 + Math.Sqrt(8100 + 2 * Gravity * fall)) / Gravity;
                    PounceMark = q.Pos + q.Vel * (HuntTimer + flight);
                }
                // Spring for it; if no honest arc exists, creep the rest of the way instead.
                if (HuntTimer <= 0 && dist > 34 * Scale)
                {
                    if (!LeapAt(PounceMark ?? q.Pos)) MoveTowardPrey(q, 60 * Scale, dt);
                }
                else if (dist > 30 * Scale) MoveTowardPrey(q, 30 * Scale, dt);
            }
            if (HuntTimer < -8) { AbandonHunt(); }
            return;
        }
        if (PreyHunt == HuntStage.Ambush)
        {
            TurnTo(q.Pos.X >= Pos.X ? 1 : -1);
            if (TryCatch(q)) return;
            if (q.Pos.DistanceTo(Pos) > 110 * Scale) { PreyHunt = HuntStage.Stalk; HuntTimer = 0.8; }
            if (HuntTimer < -8) AbandonHunt();
            return;
        }
        if (PreyHunt == HuntStage.Carry) UpdateCarry(dt);
    }

    void MoveTowardPrey(Prey q, double speed, double dt) => MoveTowardPoint(q.Pos, speed, dt);

    void MoveTowardPoint(V2 want, double speed, double dt)
    {
        if (Mode != Mode.Attached) return;
        V2 dir = (want - Pos);
        if (dir.Length < 1) return;
        dir = dir.Normalized;
        var spot = Map.NearestSpot(Pos + dir * speed * dt, 45 * Scale, null, Scale);
        if (spot is { } s)
        {
            SetAnchor(s.LoopId, s.SegIdx, s.Anchor.T, dir.X >= 0 ? 1 : -1);
            Pos = s.Point;
        }
    }

    void AbandonHunt()
    {
        Remember(ExperienceKind.HuntMissed);
        PreyHunt = HuntStage.None;
        Quarry = null;
        PounceMark = null;
        Prowess = Math.Max(0, Prowess - 0.01);
        Play(Activity.Sigh, 1.0);
    }

    public bool TryCatch(Prey p)
    {
        if (p.State != PreyState.Loose) return false;
        if (p.Pos.DistanceTo(Pos) > Prey.Info(p.Kind).CatchRadius * Scale + 6) return false;

        if (p.Kind == PreyKind.Beetle && p.Shelled)
        {
            p.Knocks++;
            Startled.Velocity = 5;
            if (p.Knocks >= 2) { p.Shelled = false; p.Vel = new V2(Rng.Range(-80, 80), 120); p.OnSurface = false; }
            return false;
        }
        if (p.Kind == PreyKind.Mosquito && p.Vel.Length > 60) return false;
        if (p.Kind == PreyKind.Ladybug && LearnedBitter) { p.Spurned = true; return false; }

        p.State = PreyState.Caught;
        p.Held = true;
        PounceMark = null;
        Quarry = p;
        PreyHunt = HuntStage.Carry;
        HuntTimer = Rng.Range(2.5, 6);
        Play(Activity.Carry, HuntTimer);
        return true;
    }

    void UpdateCarry(double dt)
    {
        if (Quarry is { State: PreyState.Caught } q)
        {
            q.Pos = Pos + new V2(Facing * 8 * Scale, -4 * Scale);
            HuntTimer -= dt;
            if (HuntTimer <= 0) BeginEat(q);
        }
        else PreyHunt = HuntStage.None;
    }

    public void BeginEat(Prey p)
    {
        Quarry = p;
        p.State = PreyState.Caught;
        PreyHunt = HuntStage.Eat;
        var info = Prey.Info(p.Kind);
        EatTimer = info.MealTime * Rng.Range(0.9, 1.15);
        p.Timer = EatTimer;
        Play(Activity.Eat, EatTimer);
    }

    void FinishMeal(Prey p)
    {
        var info = Prey.Info(p.Kind);
        if (p.Kind == PreyKind.Ladybug)
        {
            // Tastes horrible: the first is caught, tasted, and spat out none the worse.
            p.State = PreyState.Loose;
            p.Spurned = true;
            LearnedBitter = true;
            Play(Activity.Shake, 0.9);
            Startled.Velocity = 4;
            PreyHunt = HuntStage.None;
            Quarry = null;
            return;
        }
        p.State = PreyState.Eaten;
        p.Eaten01 = 1;
        Fed = Math.Min(1.5, Fed + info.Nourishment);
        Happy.Velocity = 7;
        Remember(ExperienceKind.Fed);
        Remember(ExperienceKind.HuntWon);
        AddLeftovers(p);
        Play(Activity.Wiggle, 1.4);
        PreyHunt = HuntStage.None;
        Quarry = null;
        PounceMark = null;
    }

    /// <summary>Snap at whatever the fangs pass while airborne (spec 10.2/10.3).</summary>
    public bool SnapAtPrey(double reach = 6)
    {
        foreach (var p in PreyItems)
            if (p.State == PreyState.Loose && p.Pos.DistanceTo(Pos) < (Prey.Info(p.Kind).CatchRadius + reach) * Scale)
            {
                TryCatch(p);
                if (p.State == PreyState.Caught) return true;
            }
        return false;
    }

    void UpdateWildlife(double dt)
    {
        // Never while nobody is at the machine, in the habitat, or over a full-screen app (spec 10.5).
        if (!WildlifeEnabled || InHabitat || Fullscreen || UserIdleFor > IdleLimit) return;
        WildlifeIn -= dt;
        if (WildlifeIn > 0) return;
        WildlifeIn = Math.Max(10, WildlifeFrequency * Rng.Range(0.75, 1.25));
        if (LoosePrey >= 3) return;
        ReleaseWildlife();
    }
}
