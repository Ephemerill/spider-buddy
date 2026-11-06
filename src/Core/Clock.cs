namespace SpiderBuddy.Core;

/// <summary>
/// The master frame clock (spec 1.7): one clock at 60 Hz tied to the display, 30 Hz in low power,
/// with a calm throttle that skips frames when nothing visible has changed.
/// The host drives <see cref="Tick"/> from a DwmFlush-paced loop or a waitable timer.
/// </summary>
public sealed class FrameClock
{
    public const double TargetHz = 60;
    public const double LowPowerHz = 30;

    /// <summary>App-level dt is clamped to 1/240 … 1/20 (spec 1.7).</summary>
    public const double MinDt = 1.0 / 240.0;
    public const double MaxDt = 1.0 / 20.0;

    public bool LowPower;
    public bool Paused;

    /// <summary>Skip frames when nothing visible changed for ~1 s.</summary>
    public bool CalmEnabled = true;

    double _lastMark;
    double _acc;
    public double Dt { get; private set; }
    public double Now { get; private set; }
    public long TickCount { get; private set; }

    /// <summary>True when the caller should actually update+draw this tick.</summary>
    public bool ShouldRender { get; private set; } = true;

    /// <summary>Something visible changed — cancels calm immediately (spec 1.7).</summary>
    public bool VisibleChanged { get; set; } = true;

    double _stillFor;
    int _skipPhase;

    public double Hz => LowPower ? LowPowerHz : TargetHz;
    public double FrameTime => 1.0 / Hz;

    public void Reset(double now)
    {
        _lastMark = now;
        _acc = 0;
        Now = now;
        Dt = FrameTime;
        TickCount = 0;
        VisibleChanged = true;
        _stillFor = 0;
        _skipPhase = 0;
    }

    /// <summary>
    /// Advance the clock. Returns false when the tick should be skipped entirely
    /// (calm throttle), true when the caller should update and draw.
    ///
    /// The step is a FIXED one frame long. Gating a high-rate host by raw elapsed time produces
    /// alternating 16/25 ms steps that read as stutter (spec 1.7), so a faster host simply has
    /// its extra callbacks dropped; a genuine stall is clamped to the 1/20 s ceiling instead.
    /// </summary>
    public bool Tick(double now)
    {
        double raw = now - _lastMark;
        Now = now;

        if (Paused)
        {
            _lastMark = now;
            _acc = 0;
            Dt = 0;
            ShouldRender = true;          // still draw (frozen position, animations hold)
            VisibleChanged = false;
            return true;
        }

        // A backwards jump or a real stall (debugger, sleep, display change): one clamped step.
        if (raw < 0 || raw > 0.25)
        {
            _lastMark = now;
            _acc = 0;
            Dt = M.Clamp(raw < 0 ? FrameTime : raw, MinDt, MaxDt);
            TickCount++;
            return Finish();
        }

        _acc += raw;
        _lastMark = now;

        double frame = FrameTime;
        // 0.9 rather than 1.0 so ordinary vblank jitter never drops a whole frame.
        if (_acc < frame * 0.9)
        {
            ShouldRender = false;
            return false;
        }
        _acc -= frame;
        if (_acc < 0) _acc = 0;
        if (_acc > frame * 4) _acc = 0;   // never build a backlog we then try to catch up on

        Dt = frame;                        // always exactly one frame: no 16/25 ms alternation
        TickCount++;
        return Finish();
    }

    /// <summary>Calm throttle + housekeeping bookkeeping for an accepted tick.</summary>
    bool Finish()
    {
        // Calm: nothing visible changed for ~1 s ⇒ run one of every 3 (one of every 2 in low power).
        if (VisibleChanged || !CalmEnabled)
        {
            _stillFor = 0;
            _skipPhase = 0;
            ShouldRender = true;
        }
        else
        {
            _stillFor += Dt;
            if (_stillFor < 1.0)
            {
                ShouldRender = true;
            }
            else
            {
                int modulus = LowPower ? 2 : 3;
                _skipPhase++;
                ShouldRender = (_skipPhase % modulus) == 0;
            }
        }
        VisibleChanged = false;
        return ShouldRender;
    }

    long _lastTicksStart;

    /// <summary>Called by the caller right after a tick when its draw actually put something up.</summary>
    public void MarkRendered() => _lastTicksStart = TickCount;

    /// <summary>True every 30 ticks (0.5 s) — pending nudges, rain check, music check, dormant safety.</summary>
    public bool HalfSecond => TickCount > 0 && TickCount % 30 == 0;

    /// <summary>True every 3600 ticks (60 s) — save memory if dirty.</summary>
    public bool Minute => TickCount > 0 && TickCount % 3600 == 0;

    /// <summary>At 1800 mod 3600 — save habitat knowledge if dirty.</summary>
    public bool HalfMinuteOffset => TickCount > 0 && TickCount % 3600 == 1800;
}

/// <summary>In-memory store for the headless harness (Stage 1 done-when: settings round-trip).</summary>
public sealed class MemoryTextStore : ITextFileStore
{
    readonly Dictionary<string, string> _files = new(StringComparer.OrdinalIgnoreCase);

    public string? Read(string name) => _files.TryGetValue(name, out var v) ? v : null;
    public void Write(string name, string contents) => _files[name] = contents;
    public IEnumerable<string> List(string folder) => _files.Keys.Where(k => k.StartsWith(folder + "/", StringComparison.OrdinalIgnoreCase))
        .Select(k => k[(folder.Length + 1)..]).ToList();
    public string? ReadIn(string folder, string name) => Read(folder + "/" + name);
    public void WriteIn(string folder, string name, string contents) => Write(folder + "/" + name, contents);
    public void DeleteIn(string folder, string name) => _files.Remove(folder + "/" + name);
    public string Describe() => "memory";

    public void PutRaw(string name, string json) => _files[name] = json;
    public string? Raw(string name) => Read(name);
}
