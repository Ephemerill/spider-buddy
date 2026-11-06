namespace SpiderBuddy.Core;

/// <summary>Orders emitted by scroll gestures; silk execution is implemented in Stage 8.</summary>
public enum PointerLineOrder { Up, Down }
public enum PointerMemoryEvent { Greeted, Carried, Thrown, Stroked, Scared, Played }
public enum PointerEmote { None, Sparkle, Hearts, Note, Surprise, Question }

public sealed partial class Spider
{
    public bool ClickToPickUp = true;
    public V2 Cursor { get; private set; }
    public double CursorSpeed { get; private set; }
    public bool PointerNameVisible => !IsHeld && _hoverFor > 0.7;
    public PointerEmote Emote { get; private set; }
    public double EmoteUntil { get; private set; }
    double _emoteFrom;

    // The host/silk/memory stages subscribe without introducing OS calls into the core.
    public event Action<PointerLineOrder>? ScrollOrdered;
    public event Action<PointerMemoryEvent>? PointerRemembered;
    public event Action? ContextMenuRequested;

    bool _hasCursor;
    double _cursorAt, _hoverFor;
    double _scrollLast = double.NegativeInfinity, _scrollSum, _scrollGave;
    double _nodFrom = double.NegativeInfinity, _nodFor, _nodTimes;
    double _shakeFrom = double.NegativeInfinity, _shakeFor;
    double _slowBlinkFrom = double.NegativeInfinity;

    public void Nod(int times = 2)
    {
        _nodFrom = Time;
        _nodTimes = times;
        _nodFor = 0.42 * times;
    }

    public void ShakeHead()
    {
        _shakeFrom = Time;
        _shakeFor = Rng.Range(0.8, 1);
    }

    public void SlowBlink(double delay = 0) => _slowBlinkFrom = Time + delay;

    double NodNow
    {
        get
        {
            double u = (Time - _nodFrom) / Math.Max(_nodFor, 0.01);
            return u >= 0 && u < 1 ? -0.3 * (0.5 - 0.5 * Math.Cos(u * M.Tau * _nodTimes)) : 0;
        }
    }

    double ShakeNow
    {
        get
        {
            double u = (Time - _shakeFrom) / Math.Max(_shakeFor, 0.01);
            return u >= 0 && u < 1 ? 0.22 * Math.Sin(u * M.Tau * 2.5) * Math.Sin(u * M.Pi) : 0;
        }
    }

    double SlowBlinkNow
    {
        get
        {
            double u = (Time - _slowBlinkFrom) / 1.3;
            if (u < 0 || u >= 1) return 0;
            return u < 0.3 ? M.Smoothstep(u / 0.3) : u < 0.55 ? 1 : 1 - M.Smoothstep((u - 0.55) / 0.45);
        }
    }

    bool _turnAfterPoke;
    (Activity activity, double duration)? _pointerQueued;

    public const double HardThrow = 1800;
    public const double MaxThrowSpeed = 2700;
    public bool IsHeld => Mode == Mode.Held;
    public V2 Velocity { get; set; }
    public double NoAttachFor { get; set; }
    public bool RescueLineRequested { get; private set; }
    V2 _grabOffset;

    public void BeginGrab(V2 p)
    {
        if (Cinema) return;
        _turnAfterPoke = false;
        _pointerQueued = null;
        RescueLineRequested = false;
        Mode = Mode.Held;
        Play(Activity.Idle, 1);
        _grabOffset = Pos - p;
        SetCursor(p);
        Speed = TargetSpeed = 0;
        Grasped.Velocity = 6;
        Startled.Velocity = 9;
        ShowEmote(PointerEmote.Surprise, 0.7);
        _hoverFor = 0;
    }

    public void MoveGrab(V2 p)
    {
        if (IsHeld) SetCursor(p);
    }

    public void EndGrab(V2 throwVelocity)
    {
        if (!IsHeld) return;
        double length = throwVelocity.Length;
        Velocity = length > MaxThrowSpeed ? throwVelocity * (MaxThrowSpeed / length) : throwVelocity;
        _grabOffset = V2.Zero;
        // Thrown while on a thread: a slingshot on the line (spec 5.3).
        if (WebActive)
        {
            Mode = Mode.Dangling;
            WebSlingshot = true;
            WebAngleVel = Velocity.Dot(new V2(-Math.Cos(WebAngle), -Math.Sin(WebAngle))) / Math.Max(WebLen, 24);
            WebPlan.Clear();
            WebPlan.Add(WebPlanStep.Linger(1.5));
            WebPlan.Add(WebPlanStep.Plan(WebPlanKind.ClimbHome));
            RescueLineRequested = false;
            Stretch.Velocity = -4;
            return;
        }
        Mode = Mode.Air;
        Air = AirKind.Thrown;
        NoAttachFor = 0.06;
        RescueLineRequested = Velocity.Length < HardThrow;
        PointerRemembered?.Invoke(RescueLineRequested ? PointerMemoryEvent.Carried : PointerMemoryEvent.Thrown);
        Stretch.Velocity = -4;
    }

    void UpdateHeld(double dt)
    {
        V2 previous = Pos;
        Pos = V2.Lerp(Pos, Cursor + _grabOffset, 1 - Math.Exp(-90 * dt));
        Velocity = dt > 0 ? (Pos - previous) / dt : V2.Zero;
        if (Math.Abs(Velocity.X) > 120)
        {
            WalkDir = Velocity.X >= 0 ? 1 : -1;
            Facing = WalkDir;
            Yaw.Reset(Facing);
        }
        Heading = M.Clamp(-Velocity.X * 0.0009, -0.6, 0.6) + Math.Sin(Time * 5) * 0.03;
        BobOffset = 0;
        Crouch.Step(0, dt);
        Lift.Step(0, dt);
        Pitch.Step(0, dt);
        Wag.Step(0, dt);
        Lid.Step(0, dt);
    }

    // Stage 7 extends this free-flight integrator with landing, bounce and rescue-line catches.
    void UpdatePointerFlight(double dt)
    {
        NoAttachFor = Math.Max(0, NoAttachFor - dt);
        Velocity += new V2(0, -1950) * dt;
        Velocity *= Math.Exp(-0.22 * dt);
        Pos += Velocity * dt;
        BobOffset = 0;
    }

    void UpdateHeldLegs()
    {
        double profile = SpiderRig.ProfileAmount(Facing);
        for (int i = 0; i < 8; i++)
        {
            var rest = SpiderRig.Style(SpiderRig.Rig(i, profile, Design.Look.Legs), Design.Look.Legs, default);
            ref var leg = ref Gait.Legs[i];
            leg.Foot = rest.Hip + (rest.Foot - rest.Hip) * 0.45
                + new V2(Math.Sin(Time * 9 + i * 1.1), Math.Cos(Time * 7.5 + i * 0.9)) * 3.2;
            leg.InSwing = true;
            leg.Forced = false;
            leg.Lift = 0;
            leg.LastWorldFoot = Pos + OffsetWorld(BodyLift)
                + new V2(leg.Foot.X * (Facing < 0 ? -1 : 1), leg.Foot.Y).Rotated(HeadingSpring.Value);
            leg.HasWorld = true;
        }
    }

    public void Celebrate()
    {
        _turnAfterPoke = false;
        _pointerQueued = null;
        PointerRemembered?.Invoke(PointerMemoryEvent.Greeted);
        Happy.Velocity = 10;
        ShowEmote(PointerEmote.Hearts, 1.3);
        if (Mode != Mode.Attached) return;
        if (Rng.Chance(M.Lerp(0.8, 0.3, Design.Personality.Playfulness)))
        {
            Play(Activity.Bounce, 1);
            _pointerQueued = (Activity.Wiggle, 0.9);
        }
        else
        {
            Play(Activity.Dance, 1.6);
            _pointerQueued = (Activity.ArmsUp, 0.9);
        }
    }

    /// <summary>Called only on actual pointer movement, in y-up world units.</summary>
    public void SetCursor(V2 p)
    {
        if (_hasCursor && p == Cursor) return;
        CursorSpeed = _hasCursor ? p.DistanceTo(Cursor) / Math.Max(1.0 / 240, Time - _cursorAt) : 0;
        // The first sample seeds the motion history rather than reading as an infinite dash.
        if (!_hasCursor) { _prevCursor = p; _cursorCentre = p; _cursorVel = V2.Zero; }
        Cursor = p;
        _cursorAt = Time;
        _lastUserActivity = Time;
        _hasCursor = true;
        _hoverFor = 0;
    }

    void UpdatePointer(double dt)
    {
        double speed = Time - _cursorAt > 0.1 ? 0 : CursorSpeed;
        if (!IsHeld && _hasCursor && HitTest(Cursor) && speed < 30) _hoverFor += dt;
        else _hoverFor = 0;
        if (Time >= EmoteUntil) Emote = PointerEmote.None;
        if (_pointerQueued is { } queued && ActivityTime >= ActivityDur)
        {
            _pointerQueued = null;
            Play(queued.activity, queued.duration);
        }
        if (_turnAfterPoke && ActivityTime >= ActivityDur)
        {
            _turnAfterPoke = false;
            WalkDir = -WalkDir;
            Play(Activity.Turn, 0.9);
        }
    }

    /// <summary>One swipe gives one order, unless its accumulated direction reverses (Swift scroll).</summary>
    public void Scroll(double dy, bool precise = true, bool? startsGesture = null)
    {
        if (startsGesture ?? (Time - _scrollLast > 0.35))
        {
            _scrollSum = 0;
            _scrollGave = 0;
        }
        _scrollLast = Time;
        _scrollSum += dy;
        if (Math.Abs(_scrollSum) < (precise ? 4 : 0.5)) return;
        double way = _scrollSum > 0 ? 1 : -1;
        if (way == _scrollGave) return;
        _scrollGave = way;
        var order = way > 0 ? PointerLineOrder.Up : PointerLineOrder.Down;
        ScrollOrdered?.Invoke(order);
        // One swipe = one order, obeyed at once by whatever is on the thread (spec 8.5).
        ObeyScroll(order);
    }

    public void RightClick()
    {
        // A toy on the pointer takes the right-click: it is put away, no desktop menu (spec 11.1).
        if (HandToy != ToyKind.None) { PutAwayToy(); return; }
        ContextMenuRequested?.Invoke();
    }

    /// <summary>Esc is registered by the host only while a toy is on the pointer (spec 11.1).</summary>
    public void Escape() => PutAwayToy();

    /// <summary>Personality-weighted click reactions and body-language beats from Swift poke().</summary>
    public void Poke()
    {
        PointerRemembered?.Invoke(PointerMemoryEvent.Greeted);
        _turnAfterPoke = false;
        _pointerQueued = null;
        Emote = PointerEmote.None;
        var p = Design.Personality;
        double love = M.Lerp(0.3, 1.6, p.Affection);
        double jumpy = M.Lerp(1.6, 0.25, p.Bravery);
        int choice = Rng.WeightedIndex(new double[] {
            3 * love, 2 * love, 3 * love, 1.5 * M.Lerp(0.3, 1.8, p.Playfulness),
            2 * jumpy, 1.5 * M.Lerp(0.5, 1.6, p.Curiosity), 1.5,
            1.5 * M.Lerp(0.2, 1.8, p.Playfulness), M.Lerp(1.8, 0.1, p.Affection),
            1.2 * M.Lerp(1.4, 0.3, p.Affection), M.Lerp(0.2, 1.4, p.Affection) });
        switch (choice)
        {
            case 0: Play(Activity.Wave, 1.5); Happy.Velocity = 7; ShowEmote(PointerEmote.Sparkle, 0.8); break;
            case 1: Play(Activity.ArmsUp, 1.2); Happy.Velocity = 6; ShowEmote(PointerEmote.Hearts, 1); break;
            case 2: Play(Activity.Greet, Rng.Range(1.8, 2.6)); Happy.Velocity = 7; ShowEmote(PointerEmote.Hearts, 1.2); break;
            case 3: Play(Activity.Drum, Rng.Range(2.9, 4.4)); ShowEmote(PointerEmote.Note, 1.4); break;
            case 4: Play(Activity.Startle, 0.55); Startled.Velocity = 12; ShowEmote(PointerEmote.Surprise, 0.6); break;
            case 5: Play(Activity.Curious, 1.4); ShowEmote(PointerEmote.Question, 1.1); break;
            case 6: Play(Activity.Glance, 1.2); break;
            case 7: Play(Activity.Wiggle, 0.9); Happy.Velocity = 5; break;
            case 8:
                Play(Activity.Look, 0.6);
                _turnAfterPoke = true;
                if (Rng.Chance(0.5)) { ActivityDur = 1.1; ShakeHead(); }
                break;
            case 9: Play(Activity.Look, 1.2); Nod(Rng.Chance(0.5) ? 1 : 2); break;
            case 10: Play(Activity.Stare, Rng.Range(1.8, 2.4)); SlowBlink(0.5); Happy.Velocity = 4; break;
        }
        Stretch.Velocity = -5;
    }

    void ShowEmote(PointerEmote emote, double duration)
    {
        Emote = emote;
        _emoteFrom = Time;
        EmoteUntil = Time + duration;
    }
}
