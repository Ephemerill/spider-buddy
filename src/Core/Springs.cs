namespace SpiderBuddy.Core;

/// <summary>
/// A critically-damped-ish spring — the mechanism every soft motion in the product uses (spec 1.3).
/// Semi-implicit Euler: a = (target - value) * k - velocity * c; velocity += a*dt; value += velocity*dt.
/// </summary>
public struct Spring
{
    public double Value;
    public double Velocity;
    public double K;
    public double C;

    public Spring(double value = 0, double k = 180, double c = 18)
    {
        Value = value; Velocity = 0; K = k; C = c;
    }

    public void Step(double target, double dt)
    {
        double a = (target - Value) * K - Velocity * C;
        Velocity += a * dt;
        Value += Velocity * dt;
        if (!double.IsFinite(Value)) { Value = target; Velocity = 0; }
    }

    /// <summary>An impulse on the velocity — the only way values are ever set directly (spec 4.2).</summary>
    public void Nudge(double v) => Velocity += v;

    public void Reset(double v) { Value = v; Velocity = 0; }

    public void SetStiffness(double k, double c) { K = k; C = c; }

    public bool Settled(double target, double tol = 0.01, double velTol = 0.01)
        => Math.Abs(Value - target) < tol && Math.Abs(Velocity) < velTol;
}

/// <summary>A spring over a 2-D value (spec 1.3).</summary>
public struct Spring2
{
    public V2 Value;
    public V2 Velocity;
    public double K;
    public double C;

    public Spring2(V2 value = default, double k = 180, double c = 18)
    {
        Value = value; Velocity = V2.Zero; K = k; C = c;
    }

    public void Step(V2 target, double dt)
    {
        V2 a = (target - Value) * K - Velocity * C;
        Velocity += a * dt;
        Value += Velocity * dt;
        if (!Value.IsFinite) { Value = target; Velocity = V2.Zero; }
    }

    public void Nudge(V2 v) => Velocity += v;
    public void Reset(V2 v) { Value = v; Velocity = V2.Zero; }
    public void SetStiffness(double k, double c) { K = k; C = c; }
}

/// <summary>
/// Cheap smooth 1-D noise for idle jitter (spec 1.3):
/// value(t) = 0.6 sin(x) + 0.3 sin(1.87x + 1.3) + 0.1 sin(4.31x + 2.7), x = t*freq + seed*37.13
/// Each leg owns one (seed = i*2.7, freq = 1.1 + (i%4)*0.17).
/// </summary>
public struct Wobble
{
    public double Seed;
    public double Freq;

    public Wobble(double seed, double freq) { Seed = seed; Freq = freq; }

    public static Wobble ForLeg(int i) => new(i * 2.7, 1.1 + (i % 4) * 0.17);

    public double Value(double t)
    {
        double x = t * Freq + Seed * 37.13;
        return 0.6 * Math.Sin(x) + 0.3 * Math.Sin(1.87 * x + 1.3) + 0.1 * Math.Sin(4.31 * x + 2.7);
    }

    /// <summary>Range is roughly -1..1; this keeps it inside that.</summary>
    public double ValueClamped(double t) => M.Clamp(Value(t), -1, 1);
}

/// <summary>
/// A small deterministic RNG. The test harness needs seedable injection for A/B comparison
/// (spec 1.6): the macOS tools run seeded because dictionary iteration order otherwise varies.
/// </summary>
public sealed class Rng
{
    ulong _s0, _s1;

    public Rng(ulong seed = 0) { Reseed(seed); }

    public void Reseed(ulong seed)
    {
        // splitmix64 to spread the seed over the state
        _s0 = SplitMix(ref seed);
        _s1 = SplitMix(ref seed);
        if (_s0 == 0 && _s1 == 0) _s0 = 0x9E3779B97F4A7C15UL;
    }

    static ulong SplitMix(ref ulong x)
    {
        x += 0x9E3779B97F4A7C15UL;
        ulong z = x;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
        return z ^ (z >> 31);
    }

    /// <summary>xoshiro128++ — fast, tiny, deterministic.</summary>
    public ulong NextULong()
    {
        ulong s0 = _s0, s1 = _s1;
        ulong result = Rotl(s0 + s1, 17) + s0;
        s1 ^= s0;
        _s0 = Rotl(s0, 49) ^ s1 ^ (s1 << 21);
        _s1 = Rotl(s1, 28);
        return result;
    }

    static ulong Rotl(ulong x, int k) => (x << k) | (x >> (64 - k));

    /// <summary>Uniform in [0,1).</summary>
    public double NextDouble() => (NextULong() >> 11) * (1.0 / 9007199254740992.0);

    public double Range(double lo, double hi) => lo + (hi - lo) * NextDouble();

    /// <summary>randRange from the spec: returns lo if hi is NaN, never traps on reversed bounds.</summary>
    public double RandRange(double lo, double hi)
    {
        if (double.IsNaN(hi) || double.IsNaN(lo)) return lo;
        if (hi < lo) (lo, hi) = (hi, lo);
        return lo + (hi - lo) * NextDouble();
    }

    public int RangeInt(int lo, int hiExclusive)
    {
        if (hiExclusive <= lo) return lo;
        return lo + (int)(NextDouble() * (hiExclusive - lo));
    }

    public bool Chance(double p) => p >= 1 ? true : (p <= 0 ? false : NextDouble() < p);

    public T Pick<T>(IReadOnlyList<T> list) => list.Count == 0 ? default! : list[RangeInt(0, list.Count)];

    /// <summary>Weighted pick: the first non-positive weight short-circuits nothing; total 0 returns index 0.</summary>
    public int WeightedIndex(IReadOnlyList<double> weights)
    {
        double total = 0;
        for (int i = 0; i < weights.Count; i++) if (weights[i] > 0) total += weights[i];
        if (total <= 0) return 0;
        double r = NextDouble() * total;
        for (int i = 0; i < weights.Count; i++)
        {
            double w = weights[i];
            if (w <= 0) continue;
            r -= w;
            if (r <= 0) return i;
        }
        return weights.Count - 1;
    }

    /// <summary>Gaussian-ish via the sum of three uniforms (cheap, bounded).</summary>
    public double Bell() => (NextDouble() + NextDouble() + NextDouble() - 1.5) * 0.8165;
}
