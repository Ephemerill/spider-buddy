using System.Runtime.CompilerServices;

namespace SpiderBuddy.Core;

/// <summary>
/// A 2-D vector. World units are the macOS "points" the whole geometry is written in,
/// with y pointing up (see spec D2). The host converts Win32 y-down pixels at the boundary.
/// </summary>
public struct V2 : IEquatable<V2>
{
    public double X;
    public double Y;

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public V2(double x, double y) { X = x; Y = y; }

    public static readonly V2 Zero = new(0, 0);
    public static V2 Unit(double angle) => new(Math.Cos(angle), Math.Sin(angle));

    public static V2 operator +(V2 a, V2 b) => new(a.X + b.X, a.Y + b.Y);
    public static V2 operator -(V2 a, V2 b) => new(a.X - b.X, a.Y - b.Y);
    public static V2 operator -(V2 a) => new(-a.X, -a.Y);
    public static V2 operator *(V2 a, double s) => new(a.X * s, a.Y * s);
    public static V2 operator *(double s, V2 a) => new(a.X * s, a.Y * s);
    public static V2 operator /(V2 a, double s) => new(a.X / s, a.Y / s);

    public double Dot(V2 b) => X * b.X + Y * b.Y;

    /// <summary>2-D scalar cross product (z of the 3-D cross).</summary>
    public double Cross(V2 b) => X * b.Y - Y * b.X;

    public double Length => Math.Sqrt(X * X + Y * Y);
    public double LengthSquared => X * X + Y * Y;

    /// <summary>Unit vector; the zero vector normalises to zero (never NaN).</summary>
    public V2 Normalized
    {
        get
        {
            double l = Length;
            return l <= 1e-12 ? Zero : new V2(X / l, Y / l);
        }
    }

    /// <summary>Positive = counter-clockwise (y-up).</summary>
    public V2 Rotated(double by) =>
        Math.Abs(by) < 1e-12 ? this : new V2(X * Math.Cos(by) - Y * Math.Sin(by), X * Math.Sin(by) + Y * Math.Cos(by));

    public double Angle => Math.Atan2(Y, X);

    public double DistanceTo(V2 b)
    {
        double dx = X - b.X, dy = Y - b.Y;
        return Math.Sqrt(dx * dx + dy * dy);
    }

    public double DistanceSquaredTo(V2 b)
    {
        double dx = X - b.X, dy = Y - b.Y;
        return dx * dx + dy * dy;
    }

    /// <summary>Perpendicular, rotated +90 degrees (y-up) — the "left" normal.</summary>
    public V2 Perp => new(-Y, X);

    public static V2 Lerp(V2 a, V2 b, double t) => new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t);
    public static V2 Min(V2 a, V2 b) => new(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y));
    public static V2 Max(V2 a, V2 b) => new(Math.Max(a.X, b.X), Math.Max(a.Y, b.Y));

    public bool IsFinite => double.IsFinite(X) && double.IsFinite(Y);

    public bool Equals(V2 other) => X.Equals(other.X) && Y.Equals(other.Y);
    public override bool Equals(object? obj) => obj is V2 v && Equals(v);
    public override int GetHashCode() => HashCode.Combine(X, Y);
    public static bool operator ==(V2 a, V2 b) => a.Equals(b);
    public static bool operator !=(V2 a, V2 b) => !a.Equals(b);

    public override string ToString() => $"({X:0.###}, {Y:0.###})";
}

/// <summary>A 3-D vector. Only needed by the optional "legs in the round" system (spec 4.8).</summary>
public struct V3
{
    public double X, Y, Z;
    public V3(double x, double y, double z) { X = x; Y = y; Z = z; }
    public static readonly V3 Zero = new(0, 0, 0);
    public static V3 operator +(V3 a, V3 b) => new(a.X + b.X, a.Y + b.Y, a.Z + b.Z);
    public static V3 operator -(V3 a, V3 b) => new(a.X - b.X, a.Y - b.Y, a.Z - b.Z);
    public static V3 operator *(V3 a, double s) => new(a.X * s, a.Y * s, a.Z * s);
    public double Dot(V3 b) => X * b.X + Y * b.Y + Z * b.Z;
    public V3 Cross(V3 b) => new(Y * b.Z - Z * b.Y, Z * b.X - X * b.Z, X * b.Y - Y * b.X);
    public double Length => Math.Sqrt(X * X + Y * Y + Z * Z);
    public V3 Normalized { get { double l = Length; return l <= 1e-12 ? Zero : new V3(X / l, Y / l, Z / l); } }
    public override string ToString() => $"({X:0.###}, {Y:0.###}, {Z:0.###})";
}

/// <summary>Scalar helpers used all over the behaviour code (spec 1.2).</summary>
public static class M
{
    public const double Pi = Math.PI;
    public const double Tau = Math.PI * 2;

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static int Clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Lerp(double a, double b, double t) => a + (b - a) * t;

    /// <summary>Frame-rate independent exponential approach (spec 1.2).</summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Approach(double value, double target, double rate, double dt)
        => value + (target - value) * (1 - Math.Exp(-rate * dt));

    /// <summary>Shortest signed difference between two angles, wrapped to (-pi, pi].</summary>
    public static double AngleDelta(double from, double to)
    {
        double d = (to - from) % Tau;
        if (d > Pi) d -= Tau;
        if (d <= -Pi) d += Tau;
        return d;
    }

    /// <summary>Wrap an angle into (-pi, pi].</summary>
    public static double WrapPi(double a)
    {
        a %= Tau;
        if (a > Pi) a -= Tau;
        if (a <= -Pi) a += Tau;
        return a;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static double Smoothstep(double t)
    {
        t = Clamp01(t);
        return t * t * (3 - 2 * t);
    }

    /// <summary>Smoothstep between two edges (t is remapped from (a,b) to 0..1 first).</summary>
    public static double Smoothstep(double a, double b, double t)
    {
        if (Math.Abs(b - a) < 1e-12) return t < a ? 0 : 1;
        return Smoothstep((t - a) / (b - a));
    }

    public static double EaseOutCubic(double t) { t = Clamp01(t); double u = 1 - t; return 1 - u * u * u; }
    public static double EaseInCubic(double t) { t = Clamp01(t); return t * t * t; }
    public static double EaseInOutSine(double t) { t = Clamp01(t); return -(Math.Cos(Pi * t) - 1) / 2; }

    /// <summary>Overshooting ease. easeOutBack(spec) uses overshoot 1.7 by default.</summary>
    public static double EaseOutBack(double t, double overshoot = 1.7)
    {
        t = Clamp01(t);
        double c3 = overshoot + 1;
        double u = t - 1;
        return 1 + c3 * u * u * u + overshoot * u * u;
    }

    /// <summary>Remap v from [a,b] to [lo,hi], clamped.</summary>
    public static double Remap(double v, double a, double b, double lo, double hi)
    {
        if (Math.Abs(b - a) < 1e-12) return lo;
        return Lerp(lo, hi, Clamp01((v - a) / (b - a)));
    }

    /// <summary>
    /// Project p onto segment a-b. Returns (t along the segment clamped to 0..1, perpendicular distance).
    /// </summary>
    public static (double t, double dist) ProjectOnSegment(V2 p, V2 a, V2 b)
    {
        V2 ab = b - a;
        double lenSq = ab.LengthSquared;
        if (lenSq <= 1e-12) return (0, p.DistanceTo(a));
        double t = Clamp01((p - a).Dot(ab) / lenSq);
        V2 closest = a + ab * t;
        return (t, p.DistanceTo(closest));
    }

    /// <summary>Project p onto an infinite line a-b; t is NOT clamped.</summary>
    public static double ProjectOnLine(V2 p, V2 a, V2 b)
    {
        V2 ab = b - a;
        double lenSq = ab.LengthSquared;
        if (lenSq <= 1e-12) return 0;
        return (p - a).Dot(ab) / lenSq;
    }

    public static double DistanceToSegment(V2 p, V2 a, V2 b) => ProjectOnSegment(p, a, b).dist;

    /// <summary>Move <paramref name="value"/> toward <paramref name="target"/> by at most <paramref name="maxStep"/>.</summary>
    public static double MoveToward(double value, double target, double maxStep)
    {
        double d = target - value;
        if (Math.Abs(d) <= maxStep) return target;
        return value + Math.Sign(d) * maxStep;
    }

    public static double Sign(double v) => v < 0 ? -1 : 1;

    /// <summary>Sign that returns 0 for 0 (unlike Math.Sign's double overload returning 0 too, kept explicit).</summary>
    public static double Signd(double v) => v > 0 ? 1 : (v < 0 ? -1 : 0);

    /// <summary>A quadratic Bezier point.</summary>
    public static V2 QuadPoint(V2 a, V2 c, V2 b, double t)
    {
        double u = 1 - t;
        return a * (u * u) + c * (2 * u * t) + b * (t * t);
    }

    /// <summary>A cubic Bezier point.</summary>
    public static V2 CubicPoint(V2 a, V2 c1, V2 c2, V2 b, double t)
    {
        double u = 1 - t;
        return a * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + b * (t * t * t);
    }

    /// <summary>Closest point to p on a quadratic Bezier, sampled. Returns (point, t).</summary>
    public static (V2 point, double t) ClosestOnQuad(V2 p, V2 a, V2 c, V2 b, int samples = 24)
    {
        double bestT = 0, bestD = double.MaxValue;
        for (int i = 0; i <= samples; i++)
        {
            double t = i / (double)samples;
            double d = p.DistanceSquaredTo(QuadPoint(a, c, b, t));
            if (d < bestD) { bestD = d; bestT = t; }
        }
        return (QuadPoint(a, c, b, bestT), bestT);
    }

    /// <summary>Value at parameter t on a quadratic Bezier plus its tangent.</summary>
    public static (V2 point, V2 tangent) QuadPointTangent(V2 a, V2 c, V2 b, double t)
    {
        V2 pt = QuadPoint(a, c, b, t);
        V2 tan = (c - a) * (2 * (1 - t)) + (b - c) * (2 * t);
        return (pt, tan.Normalized);
    }
}
