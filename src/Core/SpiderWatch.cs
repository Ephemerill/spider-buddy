namespace SpiderBuddy.Core;

/// <summary>The pointer-as-prey state machine (spec 5.5).</summary>
public enum CursorHunt { None, Stalking, Pouncing, Clinging }

/// <summary>
/// Stage 5.5 — watching the pointer. Interest builds while the pointer hangs about; the body turns
/// to it continuously through the front view, the head leads the legs, a whip makes it hop, a stroke
/// makes it blush, and a fidget close by gets stalked, pounced on and clung to.
/// All of it is portable: the host only supplies pointer samples.
/// </summary>
public sealed partial class Spider
{
    public const double InterestRange = 170;   // × scale
    public const double HuntRange = 250;       // × scale

    public bool FollowCursor = true;           // "Watch the Cursor"
    public bool ApproachCursor;                // "Come to the Cursor"
    public bool PounceOnCursor = true;         // "Pounce on the Cursor"
    public bool CursorFree = true;             // false inside a box / outside the tank

    public double Interest { get; private set; }
    public double InterestBearing { get; private set; } = 1;
    public double InterestSide { get; private set; } = 1;
    public double InterestYawTarget { get; private set; } = 1;
    public double HeadYawTarget { get; private set; } = 1;
    public CursorHunt Hunt { get; private set; }
    public double PettingScore => _pettingScore;
    public bool IsClinging => Mode == Mode.Clinging;
    public bool IsWatching => Mode == Mode.Attached && Interest > 0.5 && Speed < 1;
    public double CursorStillFor => _cursorStillFor;

    V2 _cursorVel, _prevCursor, _cursorCentre;
    double _cursorStillFor;
    double _lastUserActivity = -99;
    double _wiggleScore, _cursorNearFor, _boredAfter = 16;
    int _wiggleX, _wiggleY;
    Spring _interestNose = new(0, 260, 26);
    Spring _interestLean = new(0, 200, 22);
    double _headPinnedFor, _sideSwitchFor, _stanceOffFor;
    double _pettingScore, _lastPetSign;
    bool _rushed;
    double _huntSince, _nextHuntAt = 8;
    double _clingSince, _clingFor = 4, _clingShake;
    V2 _clingShakeSign, _clingOffset;
    double _whipAt = -99;

    /// <summary>Nothing the pointer does gets through: a hunt, a job, a nap or a fast scurry.</summary>
    bool Preoccupied
    {
        get
        {
            if (Mode != Mode.Attached) return true;
            if (Activity is Activity.Sleep or Activity.Eat or Activity.Watch or Activity.Peekaboo
                or Activity.Roll or Activity.Spin or Activity.Crouch or Activity.Shoot or Activity.Fasten
                or Activity.Scurry or Activity.Startle or Activity.Stretch or Activity.Shake
                or Activity.Bounce or Activity.Dance or Activity.Drum or Activity.Groove) return true;
            return Speed > WalkSpeed * 1.5;
        }
    }

    /// <summary>Every frame: motion history, petting, the whip, the hunt and the interest itself.</summary>
    void UpdateWatch(double dt)
    {
        double sc = Scale;
        V2 delta = Cursor - _prevCursor;
        _prevCursor = Cursor;
        if (dt > 0) _cursorVel = V2.Lerp(_cursorVel, delta / dt, 1 - Math.Exp(-18 * dt));
        _cursorStillFor = _cursorVel.Length < 40 ? _cursorStillFor + dt : 0;

        UpdatePetting(dt, delta);

        // A pointer whipped right across its face: a small startled hop, not a run (spec 5.5).
        if (!IsHeld && !IsClinging && Hunt == CursorHunt.None && !Preoccupied
            && Cursor.DistanceTo(Pos) < 95 * sc && _cursorVel.Length > 1400 * sc
            && Time - _whipAt > 1.2)
        {
            _whipAt = Time;
            Play(Activity.Hop, 0.38);
            Startled.Velocity = 7;
            ShowEmote(PointerEmote.Surprise, 0.5);
            PointerRemembered?.Invoke(PointerMemoryEvent.Scared);
        }

        if (Hunt == CursorHunt.Stalking) UpdateStalk();
        else if (Hunt == CursorHunt.Pouncing) UpdatePounce();

        UpdateInterest(dt);
    }

    void UpdatePetting(double dt, V2 delta)
    {
        double sc = Scale;
        bool near = Cursor.DistanceTo(Pos) < 40 * sc;
        if (!near) _lastPetSign = 0;
        if (near && delta.Length > 1.2 && _cursorVel.Length < 700 * sc)
        {
            double sign = delta.X >= 0 ? 1 : -1;
            if (sign != _lastPetSign)
            {
                if (_lastPetSign != 0) _pettingScore = Math.Min(_pettingScore + 0.42, 1.6);
                _lastPetSign = sign;
            }
        }
        _pettingScore = Math.Max(0, _pettingScore - dt * 0.55);

        // A pointer dashed across it at speed is being chased about, not stroked.
        if (!near) _rushed = false;
        else if (!_rushed && _cursorVel.Length > 1400 * sc && !IsHeld && !IsClinging
                 && Hunt == CursorHunt.None && _pettingScore < 0.4)
        {
            _rushed = true;
            PointerRemembered?.Invoke(PointerMemoryEvent.Played);
        }

        if (_pettingScore > 0.85 && Hunt == CursorHunt.None)
        {
            PointerRemembered?.Invoke(PointerMemoryEvent.Stroked);
            Happy.Value = Math.Max(Happy.Value, 0.85);
            if (Emote == PointerEmote.None) ShowEmote(PointerEmote.Hearts, 1.0);
            if (Mode == Mode.Attached && Activity is not (Activity.Wiggle or Activity.Dance or Activity.Groove)
                && Rng.Chance(dt * 1.5))
            {
                Play(Rng.Chance(0.6) || Activity == Activity.Dance ? Activity.Wiggle : Activity.Dance, 0.9);
            }
        }
    }

    void UpdateInterest(double dt)
    {
        double sc = Scale;
        double d = Cursor.DistanceTo(Pos);

        // Fidgeting: every quick reversal near it counts; the score fades fast, so only a proper
        // back-and-forth wiggle adds up (spec 5.5).
        if (d < HuntRange * sc)
        {
            int sx = _cursorVel.X > 150 ? 1 : _cursorVel.X < -150 ? -1 : 0;
            int sy = _cursorVel.Y > 150 ? 1 : _cursorVel.Y < -150 ? -1 : 0;
            if (sx != 0 && sx != _wiggleX) { if (_wiggleX != 0) _wiggleScore += 0.3; _wiggleX = sx; }
            if (sy != 0 && sy != _wiggleY) { if (_wiggleY != 0) _wiggleScore += 0.3; _wiggleY = sy; }
        }
        else { _wiggleX = _wiggleY = 0; }
        _wiggleScore = Math.Max(0, Math.Min(3, _wiggleScore) - dt * 0.7);

        if (d < InterestRange * sc) _cursorNearFor += dt;
        else
        {
            _cursorNearFor = Math.Max(0, _cursorNearFor - dt * 3);
            if (_cursorNearFor == 0) _boredAfter = Rng.Range(10, 22);
        }
        bool bored = _cursorNearFor > _boredAfter && _wiggleScore < 0.5;

        bool busy = Preoccupied;
        bool wants = FollowCursor && !busy && !bored && d < InterestRange * sc && CursorFree
                     && Time - _lastUserActivity < 8 && Hunt == CursorHunt.None;
        Interest = M.Approach(Interest, wants ? 1 : 0, wants ? 6 : busy ? 4 : 1.2, dt);
        _cursorCentre = V2.Lerp(_cursorCentre, Cursor, 1 - Math.Exp(-7 * dt));

        double nose = 0;
        if (Interest > 0.01 && Mode == Mode.Attached)
        {
            // The pointer's bearing in the ledge's frame: +x along the ledge, +y away from it.
            V2 a = (Cursor - Pos).Rotated(-Heading);
            double r = Math.Max(a.Length, 30 * sc);
            double c = a.X / r, s = a.Y / r;
            nose = M.Clamp(Math.Atan(0.9 * s), -0.6, 0.75);
            HeadYawTarget = 0.9 * c;

            if (Speed > 1 || Activity is Activity.Walk or Activity.Scurry or Activity.Sneak)
            {
                // Never walk backwards with its eyes on you: three-quarters round at most.
                c = Facing * Math.Max(Facing * c, 0.45);
                HeadYawTarget = Facing * Math.Max(Facing * HeadYawTarget, 0.3);
            }

            InterestBearing = M.Approach(InterestBearing, c, 2.4, dt);

            bool gesturing = Activity is Activity.Wave or Activity.Greet or Activity.ArmsUp
                or Activity.Curious or Activity.Dance or Activity.Wiggle;
            bool pinned = _headPinnedFor > 0.12;
            double lead = pinned ? c : InterestBearing;
            if (lead * InterestSide < -(pinned ? 0.05 : 0.3) && !gesturing)
            {
                _sideSwitchFor += dt;
                if (_sideSwitchFor > (pinned ? 0.08 : 0.5))
                {
                    InterestSide = -InterestSide;
                    _sideSwitchFor = 0;
                }
            }
            else _sideSwitchFor = Math.Max(0, _sideSwitchFor - dt * 2);

            // The legs come round after the head, and only once it has gone well round: small
            // movements are all in the upper body. Straight overhead keeps the side it had.
            double stance = InterestSide * Math.Max(InterestSide * InterestBearing, 0.12) * 0.88;
            double off = Math.Abs(stance - InterestYawTarget);
            _stanceOffFor = off > 0.12 ? _stanceOffFor + dt : 0;
            if ((stance >= 0) != (InterestYawTarget >= 0) || off > 0.3 || _stanceOffFor > 1.2)
            {
                InterestYawTarget = stance;
                _stanceOffFor = 0;
            }

            double headWanted = HeadYawTarget - InterestYawTarget;
            _headPinnedFor = Math.Abs(headWanted) >= 0.6 ? _headPinnedFor + dt : 0;
        }

        if (Interest < 0.05)
        {
            InterestSide = Facing >= 0 ? 1 : -1;
            InterestBearing = Yaw.Value;
            InterestYawTarget = Yaw.Value;
            HeadYawTarget = Yaw.Value;
            _sideSwitchFor = 0;
        }
        _interestNose.Step(nose * Interest, dt);
        _interestLean.Step(Interest * Math.Max(0, InterestBearing) * 0.6, dt);
        if (Interest > 0.01) Look = (Cursor - Pos).Normalized;

        bool fidgeting = _wiggleScore > 1.8 && _cursorNearFor > 0.6;
        if (PounceOnCursor && FollowCursor && Hunt == CursorHunt.None && !Preoccupied
            && Time > _nextHuntAt && Interest > 0.5 && fidgeting
            && d < HuntRange * sc && CursorFree && Rng.Chance(dt * 2.5))
            BeginHunt();
    }

    /// <summary>Locks on: a freeze, then the creep (spec 5.5).</summary>
    public void BeginHunt()
    {
        Hunt = CursorHunt.Stalking;
        _huntSince = Time;
        _wiggleScore = 0;
        Play(Activity.Look, Rng.Range(0.5, 0.9));
        PointerRemembered?.Invoke(PointerMemoryEvent.Played);
    }

    public void EndHunt(double nextIn = 10)
    {
        Hunt = CursorHunt.None;
        _nextHuntAt = Time + nextIn / M.Lerp(0.6, 1.5, Design.Personality.Playfulness);
        _wiggleScore = 0;
    }

    void UpdateStalk()
    {
        double dx = Cursor.X - Pos.X;
        if (Math.Abs(dx) > 2) WalkDir = dx >= 0 ? 1 : -1;
        if (Activity is not (Activity.Sneak or Activity.Look)) Play(Activity.Sneak, 0.9);
        double d = Cursor.DistanceTo(Pos);
        // Poised, it springs (spec 5.5: stalk → pounce → cling).
        if (Time - _huntSince > 0.7 && d < 120 * Scale && Activity != Activity.Crouch)
            StartPounce();
    }

    void StartPounce()
    {
        Hunt = CursorHunt.Pouncing;
        _huntSince = Time;
        Mode = Mode.Air;
        Air = AirKind.Leap;
        NoAttachFor = 0.6;
        const double flight = 0.36;
        V2 to = Cursor + new V2(0, 10 * Scale) - Pos;
        Velocity = new V2(to.X / flight, to.Y / flight + 0.5 * 1950 * flight);
        Play(Activity.Pounce, 0.5);
    }

    void UpdatePounce()
    {
        if (Mode == Mode.Clinging) return;
        if (Mode == Mode.Attached) { EndHunt(10); return; }
        if (Mode == Mode.Air && Cursor.DistanceTo(Pos) < 34 * Scale) BeginCling();
    }

    /// <summary>Hooks on with the front legs and hangs off the pointer (spec 5.5).</summary>
    public void BeginCling()
    {
        Mode = Mode.Clinging;
        Hunt = CursorHunt.Clinging;
        _clingSince = Time;
        _clingFor = Rng.Range(3, 6);
        _clingShake = 0;
        _clingShakeSign = V2.Zero;
        _clingOffset = Pos - Cursor;
        Velocity = V2.Zero;
        ShowEmote(PointerEmote.Hearts, 1.0);
        Play(Activity.Cling, _clingFor);
    }

    void UpdateCling(double dt)
    {
        NoAttachFor = Math.Max(0, NoAttachFor - dt);
        // The grip blends from where it caught on to its mouth on the hotspot.
        _clingOffset = V2.Lerp(_clingOffset, new V2(0, -16 * Scale), 1 - Math.Exp(-6 * dt));
        V2 target = Cursor + _clingOffset;
        V2 previous = Pos;
        Pos = V2.Lerp(Pos, target, 1 - Math.Exp(-12 * dt));
        Velocity = dt > 0 ? (Pos - previous) / dt : V2.Zero;
        Heading = M.Clamp(-_cursorVel.X * 0.0005, -0.5, 0.5) + Math.Sin(Time * 4) * 0.04;
        BobOffset = 0;

        // Shaking the pointer back and forth wears the grip down.
        if (Math.Abs(_cursorVel.X) > 500 * Scale)
        {
            int sx = _cursorVel.X > 0 ? 1 : -1;
            if (sx != (int)_clingShakeSign.X)
            {
                if (_clingShakeSign.X != 0) _clingShake += 0.55;
                _clingShakeSign = new V2(sx, 0);
            }
        }
        _clingShake += dt * 0.06;
        if (_clingShake > 2 || Time - _clingSince > _clingFor * 2.5) DropFromCling();
    }

    /// <summary>Lets go and drops away on a line (spec 5.5).</summary>
    public void DropFromCling()
    {
        if (Mode != Mode.Clinging) return;
        Hunt = CursorHunt.None;
        _nextHuntAt = Time + 20;
        Mode = Mode.Air;
        Air = AirKind.Fall;
        Velocity = new V2(_cursorVel.X * 0.25, 60 * Scale);
        NoAttachFor = 0.2;
        RescueLineRequested = true;
        Startled.Velocity = 5;
    }

    /// <summary>Front two pairs hooked round the hotspot, the rest tucked and kicking.</summary>
    void UpdateClingLegs()
    {
        V2 body = Pos + OffsetWorld(BodyLift);
        double fs = Facing < 0 ? -1 : 1;
        for (int i = 0; i < 8; i++)
        {
            ref var leg = ref Gait.Legs[i];
            V2 world;
            if (i < 4)
                world = Cursor + new V2((i - 1.5) * 5 * Scale, (i % 2 == 0 ? 5 : -5) * Scale);
            else
                world = body + new V2((i - 5.5) * 4, -8 + Math.Sin(Time * 10 + i) * 2.5) * Scale;
            V2 local = (world - body).Rotated(-HeadingSpring.Value);
            if (fs < 0) local = new V2(-local.X, local.Y);
            leg.Foot = local;
            leg.Lift = i < 4 ? 0 : Math.Sin(Time * 10 + i) * 1.5;
            leg.InSwing = true;
            leg.Forced = false;
            leg.LastWorldFoot = world;
            leg.HasWorld = true;
        }
    }
}
