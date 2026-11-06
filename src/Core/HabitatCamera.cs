namespace SpiderBuddy.Core;

/// <summary>
/// Where the glass is looking, and how it follows (Swift HabitatCamera): a dead zone across the
/// middle, a critically damped spring (ω=2.5), a speed cap, free panning with a flick, glide and
/// recall, and a drift back after ninety seconds.
/// </summary>
public sealed class HabitatCamera
{
    public enum Mode { Follow, Free, Glide }

    public V2 Origin { get; private set; }
    public SizeD View { get; private set; } = new(860, 516);
    public SizeD World { get; private set; } = new(3000, 1200);
    public Mode CurrentMode { get; private set; } = Mode.Follow;
    public bool GlideThenFollow { get; private set; }

    V2 _target, _vel, _coast;
    bool _engaged;
    public double LastTouched { get; private set; }
    public double Clock { get; private set; }
    public static double ReturnAfter => 90;

    public Rect Visible => new(Origin.X, Origin.Y, View.Width, View.Height);
    public Rect DeadZone => Visible.Inset(View.Width * .22, View.Height * .25);
    Rect ComfortZone => Visible.Inset(View.Width * .3, View.Height * .3);
    public V2 Velocity => _vel;

    public bool Resting => CurrentMode switch
    {
        Mode.Glide => false,
        Mode.Free => _coast.LengthSquared < 1,
        _ => !_engaged
    };

    public void SetWorld(SizeD size)
    {
        World = size;
        Origin = Clamped(Origin);
        _target = Clamped(_target);
    }

    public void SetView(SizeD size, V2 shift = default)
    {
        if (size.Width <= 1 || size.Height <= 1) return;
        View = size;
        Origin = Clamped(Origin + shift);
        _target = Clamped(_target + shift);
    }

    public void Jump(V2 origin)
    {
        Origin = Clamped(origin); _target = Origin; _vel = _coast = V2.Zero; _engaged = false;
    }

    public V2 Centring(V2 p) => Clamped(p - new V2(View.Width / 2, View.Height / 2));

    public void Glide(V2 worldPoint, bool thenFollow)
    {
        _target = Centring(worldPoint); _coast = V2.Zero; CurrentMode = Mode.Glide;
        GlideThenFollow = thenFollow; LastTouched = Clock;
    }

    public void Recall(V2 spider) => Glide(spider, true);

    public void BeginPan()
    {
        CurrentMode = Mode.Free; _engaged = false; _coast = _vel = V2.Zero; LastTouched = Clock;
    }

    public void Pan(V2 delta)
    {
        if (CurrentMode != Mode.Free) BeginPan();
        Origin = Clamped(Origin + delta); _target = Origin; LastTouched = Clock;
    }

    public void EndPan(V2 velocity)
    {
        _coast = ClampLength(velocity, 3000);
        if (_coast.Length < 40) _coast = V2.Zero;
        LastTouched = Clock;
    }

    public void Touch() => LastTouched = Clock;

    /// <summary>Advance one frame. Returns true when it moved.</summary>
    public bool Update(double dt, V2? spider, bool follows)
    {
        Clock += Math.Max(0, dt);
        var was = Origin;
        switch (CurrentMode)
        {
            case Mode.Free:
                if (_coast.LengthSquared >= 1)
                {
                    var before = Origin;
                    Origin = Clamped(Origin + _coast * dt);
                    if (Math.Abs(Origin.X - (before.X + _coast.X * dt)) > .01) _coast.X = 0;
                    if (Math.Abs(Origin.Y - (before.Y + _coast.Y * dt)) > .01) _coast.Y = 0;
                    _coast *= Math.Exp(-4.5 * dt);
                    if (_coast.Length < 8) _coast = V2.Zero;
                    _target = Origin;
                }
                if (follows && spider is { } s && _coast.LengthSquared < 1)
                {
                    if (ComfortZone.Contains(s)) { CurrentMode = Mode.Follow; _engaged = false; }
                    else if (!Visible.Inset(-40).Contains(s) && Clock - LastTouched > ReturnAfter) Recall(s);
                }
                break;
            case Mode.Glide:
                if (GlideThenFollow && spider is { } gs) _target = Centring(gs);
                if (Step(dt)) { CurrentMode = GlideThenFollow ? Mode.Follow : Mode.Free; _engaged = false; LastTouched = Clock; }
                break;
            case Mode.Follow:
                if (follows && spider is { } fs)
                {
                    var dz = DeadZone;
                    if (!dz.Contains(fs))
                    {
                        var t = _engaged ? _target : Origin;
                        if (fs.X > dz.MaxX) t.X = fs.X - View.Width * .4;
                        else if (fs.X < dz.MinX) t.X = fs.X - View.Width * .6;
                        if (fs.Y > dz.MaxY) t.Y = fs.Y - View.Height * .4;
                        else if (fs.Y < dz.MinY) t.Y = fs.Y - View.Height * .6;
                        _target = Clamped(t); _engaged = true;
                    }
                }
                if (_engaged && Step(dt)) _engaged = false;
                break;
        }
        return (Origin - was).LengthSquared > 1e-6;
    }

    bool Step(double dt)
    {
        const double omega = 2.5, maxSpeed = 1600;
        double k = omega * omega, c = 2 * omega;
        _vel += ((_target - Origin) * k - _vel * c) * dt;
        _vel = ClampLength(_vel, maxSpeed);
        var before = Origin + _vel * dt;
        Origin = Clamped(before);
        if (Math.Abs(Origin.X - before.X) > .01) _vel.X = 0;
        if (Math.Abs(Origin.Y - before.Y) > .01) _vel.Y = 0;
        if ((_target - Origin).Length < .8 && _vel.Length < 8)
        {
            Origin = _target; _vel = V2.Zero; return true;
        }
        return false;
    }

    V2 Clamped(V2 o)
    {
        double Fit(double v, double span, double glass) => span <= glass ? (span - glass) / 2 : Math.Min(Math.Max(v, 0), span - glass);
        return new V2(Fit(o.X, World.Width, View.Width), Fit(o.Y, World.Height, View.Height));
    }

    static V2 ClampLength(V2 v, double max)
    {
        double l = v.Length;
        return l > max ? v / l * max : v;
    }

    public string SaveJson() => $"{{\"x\":{Origin.X.ToString(System.Globalization.CultureInfo.InvariantCulture)},\"y\":{Origin.Y.ToString(System.Globalization.CultureInfo.InvariantCulture)}}}";
}
