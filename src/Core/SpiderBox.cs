namespace SpiderBuddy.Core;

public enum VisitorPhase { Arriving, Playing, Leaving }

public sealed class Visitor
{
    public int Id;
    public string Name = "visitor";
    public VisitorPhase Phase = VisitorPhase.Arriving;
    public double Age;
    public bool Greeted, Tagged, Departed, Dismissed;
    public V2 Pos;
    public double LeaveAt = -1;
}

/// <summary>Stage 15 — the box, visitors and thoughts (spec 15).</summary>
public sealed partial class Spider
{
    public Rect? Box { get; private set; }
    public bool Confined => Box is not null;
    public bool HangOnly { get; private set; }
    public int BoxReturns { get; private set; }
    public double BoxDecisionScale => Confined ? 0.45 : 1;

    public bool VisitorsEnabled;
    public int MaxVisitors = 5;
    public double VisitFrequency = 3600;
    public double VisitStay = 300;
    public double VisitorTimer;
    public int VisitorSerial;
    public readonly List<Visitor> Visitors = new();
    public int VisitorsDismissed { get; private set; }

    public void SetBox(Rect? box)
    {
        if (InHabitat) { Box = null; InBox = false; return; }
        Box = box;
        InBox = box is not null;
        Chill = box is null ? 1 : 0.4;
        HangOnly = box is { } b && !Map.SampleSpots(30, true, Scale).Any(s => b.Contains(s.Point));
    }

    public void FreeBox() => SetBox(null);

    public bool InsideBox => Box?.Contains(Pos) ?? true;

    /// <summary>First thing on its mind when it finds itself outside (spec 15.1).</summary>
    public bool ReturnToBox()
    {
        if (Box is not { } b || b.Contains(Pos)) return false;
        var inside = Map.SampleSpots(30, true, Scale)
            .Where(s => b.Contains(s.Point))
            .OrderBy(s => s.Point.DistanceTo(Pos))
            .FirstOrDefault();
        if (inside.Point == V2.Zero && inside.LoopId is null) return false;
        BoxReturns++;
        if (LeapAt(inside.Point)) return true;
        if (Map.NearestSpot(Pos, 80 * Scale, null, Scale) is { } near)
        {
            MoveTowardPoint(inside.Point, 50 * Scale, 1.0 / 60);
            return true;
        }
        return false;
    }

    public Visitor? SpawnVisitor()
    {
        if (!VisitorsEnabled || Visitors.Count >= MaxVisitors) return null;
        var r = Map.WorldBounds;
        var v = new Visitor
        {
            Id = ++VisitorSerial,
            Name = $"visitor {VisitorSerial}",
            Pos = new V2(Rng.Chance(0.5) ? r.MinX + 12 : r.MaxX - 12, r.Y + r.H * 0.5),
            Phase = VisitorPhase.Arriving
        };
        Visitors.Add(v);
        return v;
    }

    public void DismissVisitors()
    {
        foreach (var v in Visitors)
        {
            v.Phase = VisitorPhase.Leaving;
            v.Dismissed = true;
            v.LeaveAt = v.Age + 2;
        }
        VisitorsDismissed += Visitors.Count;
    }

    void UpdateVisitors(double dt)
    {
        if (!VisitorsEnabled) return;
        VisitorTimer += dt;
        if (VisitorTimer >= VisitFrequency)
        {
            VisitorTimer = 0;
            SpawnVisitor();
        }
        for (int i = Visitors.Count - 1; i >= 0; i--)
        {
            var v = Visitors[i];
            v.Age += dt;
            if (v.Phase == VisitorPhase.Arriving && v.Age > 1.5)
            {
                v.Phase = VisitorPhase.Playing;
                v.Greeted = true;
            }
            if (v.Phase == VisitorPhase.Playing && !v.Tagged && v.Age > 2.4)
                v.Tagged = true;
            if (v.Phase != VisitorPhase.Leaving && v.Age > VisitStay) v.Phase = VisitorPhase.Leaving;
            if (v.Phase == VisitorPhase.Leaving
                && (v.LeaveAt >= 0 ? v.Age > v.LeaveAt : v.Age > VisitStay + 3))
            {
                v.Departed = true;
                Visitors.RemoveAt(i);
            }
        }
    }

    public void ThinkOf(ThoughtKind kind, string? text = null)
    {
        CurrentThought = kind;
        CurrentThoughtText = text;
        _thoughtFrom = Time;
        _thoughtUntil = Time + 3.2;
    }
}
