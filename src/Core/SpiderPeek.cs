namespace SpiderBuddy.Core;

public enum PeekPhase { None, Approach, Hide, Wait, Burst, Back }

/// <summary>Stage 9 — hide behind a window edge and burst out at the pointer (spec 9).</summary>
public sealed partial class Spider
{
    public PeekPhase Peek;
    public double PeekTimer;
    public double PeekWantsUntil;
    public int PeekBursts, PeekBurstsDone;
    public V2 PeekEdge;
    public Rect PeekRect;
    public bool PeekHiddenNow => Peek is PeekPhase.Hide or PeekPhase.Wait or PeekPhase.Back;

    V2 _peekStart;
    double _peekSide;

    /// <summary>An edge on a window near enough to slip behind (spec 9).</summary>
    bool FindPeekEdge(double reach)
    {
        bool found = false;
        double best = double.MaxValue;
        foreach (var id in Map.Order)
        {
            var loop = Map.Loop(id);
            if (loop is null || !loop.Kind.OnWindow() || !loop.Rect.IsValid) continue;
            foreach (double x in new[] { loop.Rect.MinX, loop.Rect.MaxX })
            {
                double d = Math.Abs(x - Pos.X) + Math.Abs(loop.Rect.Mid.Y - Pos.Y) * 0.25;
                if (d > reach || d >= best) continue;
                double y = M.Clamp(Pos.Y, loop.Rect.MinY + 12, loop.Rect.MaxY - 12);
                if (Math.Abs(y - Pos.Y) > reach) continue;
                best = d;
                PeekEdge = new V2(x, y);
                PeekRect = loop.Rect;
                _peekSide = x >= Pos.X ? 1 : -1;   // which way it looks out
                found = true;
            }
        }
        return found;
    }

    /// <summary>Creep to an edge, slip behind it, then burst out two to four times (spec 9).</summary>
    public bool StartPeekaboo(double reach = 260)
    {
        if (Peek != PeekPhase.None || Mode != Mode.Attached) return false;
        if (!FindPeekEdge(reach * Scale)) return false;
        Peek = PeekPhase.Approach;
        PeekTimer = 1.1;
        PeekBursts = Rng.RangeInt(2, 5);
        PeekBurstsDone = 0;
        _peekStart = Pos;
        PendingJump = null;
        Play(Activity.Peekaboo, 1.4);
        return true;
    }

    public void AbortPeek()
    {
        if (Peek == PeekPhase.None) return;
        Peek = PeekPhase.None;
        PeekHiddenNowSet(false);
        Pos = PeekEdge + new V2(_peekSide * -10, 0);
    }

    void PeekHiddenNowSet(bool hidden) => _peekHidden = hidden;

    bool _peekHidden;

    /// <summary>The sequence runs on its own clock while the body is held at the edge.</summary>
    void UpdatePeek(double dt)
    {
        PeekTimer -= dt;
        switch (Peek)
        {
            case PeekPhase.Approach:
                Pos = V2.Lerp(_peekStart, PeekEdge + new V2(_peekSide * 12, 0),
                    1 - Math.Exp(-4.5 * (1.1 - Math.Max(0, PeekTimer))));
                if (PeekTimer <= 0) { Peek = PeekPhase.Hide; PeekTimer = 0.75; _peekStart = Pos; }
                break;

            case PeekPhase.Hide:
                Pos = PeekEdge + new V2(-_peekSide * 14, 0);
                _peekHidden = true;
                if (PeekTimer <= 0) { Peek = PeekPhase.Wait; PeekTimer = 0.55; }
                break;

            case PeekPhase.Wait:
                Pos = PeekEdge + new V2(-_peekSide * 14, 0);
                _peekHidden = true;
                if (PeekTimer <= 0) { Peek = PeekPhase.Burst; PeekTimer = 0.45; _peekHidden = false; PeekBurstsDone++; }
                break;

            case PeekPhase.Burst:
                Pos = PeekEdge + new V2(_peekSide * 26, 0);
                if (PeekTimer <= 0)
                {
                    if (PeekBurstsDone >= PeekBursts) FinishPeek();
                    else { Peek = PeekPhase.Back; PeekTimer = 0.32; }
                }
                break;

            case PeekPhase.Back:
                Pos = PeekEdge + new V2(-_peekSide * 14, 0);
                _peekHidden = true;
                if (PeekTimer <= 0) { Peek = PeekPhase.Wait; PeekTimer = 0.5; }
                break;
        }
    }

    void FinishPeek()
    {
        Peek = PeekPhase.None;
        _peekHidden = false;
        Pos = PeekEdge + new V2(_peekSide * 16, 0);
        Play(Activity.Wiggle, 1.1);
        Happy.Velocity = 5;
    }

    /// <summary>Called from the decision loop; asked or spontaneous (spec 9).</summary>
    public bool MaybePeekaboo()
    {
        if (Peek != PeekPhase.None || Mode != Mode.Attached) return false;
        bool asked = Time < PeekWantsUntil;
        bool someoneAbout = Cursor.DistanceTo(Pos) < 520 * Scale && Time - _cursorAt < 20;
        if (!asked && !someoneAbout) return false;
        if (!asked)
        {
            double chance = Math.Min(1, M.Lerp(0.03, 0.14, Design.Personality.Playfulness)) * 0.5;
            if (!Rng.Chance(chance)) return false;
        }
        if (StartPeekaboo(asked ? 600 : 260)) return true;
        // Asked and no edge here: it goes looking.
        if (asked)
        {
            var spot = Map.NearestSpot(Pos + new V2(Rng.Chance(0.5) ? 320 * Scale : -320 * Scale, 0), 420 * Scale, null, Scale);
            if (spot is { } target) StartJump(target.Point);
        }
        return false;
    }
}
