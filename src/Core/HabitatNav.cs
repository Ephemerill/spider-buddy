namespace SpiderBuddy.Core;

/// <summary>
/// A* over the tank's surface spots (Swift TankNav). States are (spot, direction along its loop).
/// Walks, turns, junction hops, short leaps between nearby surfaces and shut-door passages.
/// </summary>
public sealed class TankNav
{
    public const double Spacing = 30;
    public const double LeapRange = 460;
    public const double Near = 16;
    public const float TurnCost = 55;

    public readonly double Scale;
    public readonly List<string> LoopIds = new();
    public readonly List<Spot> Nodes = new();
    readonly Dictionary<string, List<int>> _byLoop = new();
    readonly List<(int a, int b, float cost)> _edges = new();
    readonly Dictionary<int, List<(int to, float cost, NavEdge kind)>> _graph = new();
    public int States => Nodes.Count * 2;
    public double BuildMs { get; private set; }

    public enum NavEdge { Walk, Turn, Hop, Leap, Door }

    public TankNav(SurfaceMap map, double scale)
    {
        var started = Environment.TickCount64;
        Scale = scale;
        foreach (var loop in map.AllLoops)
        {
            LoopIds.Add(loop.Id);
            _byLoop[loop.Id] = new();
            foreach (var s in map.SampleSpots(Spacing, true, scale).Where(s => s.LoopId == loop.Id))
            {
                int idx = Nodes.Count;
                Nodes.Add(s);
                _byLoop[loop.Id].Add(idx);
            }
        }
        // Walk edges between adjacent spots on a loop.
        foreach (var (loopId, ids) in _byLoop)
        {
            var loop = map.Loop(loopId);
            if (loop is null) continue;
            ids.Sort((a, b) =>
            {
                int c = Nodes[a].SegIdx.CompareTo(Nodes[b].SegIdx);
                return c != 0 ? c : Nodes[a].Anchor.T.CompareTo(Nodes[b].Anchor.T);
            });
            for (int i = 0; i < ids.Count; i++)
            {
                int a = ids[i], b = ids[(i + 1) % ids.Count];
                if (a == b || (!loop.Closed && i == ids.Count - 1)) continue;
                float d = (float)Nodes[a].Point.DistanceTo(Nodes[b].Point);
                if (d > Spacing * 3.2 && loop.Closed) continue;
                AddEdge(a, b, d + 1, NavEdge.Walk, both: true);
            }
            if (!loop.Closed && ids.Count > 0)
                AddTurn(ids[0]); AddTurn(ids[^1]);
        }
        // Junction edges: nearest spot to each junction vertex on each side.
        foreach (var j in map.Junctions)
        {
            int a = NearestNode(j.FromLoop, j.At, 80), b = NearestNode(j.ToLoop, j.At, 80);
            if (a >= 0 && b >= 0 && a != b) AddEdge(a, b, 12 + (float)Nodes[a].Point.DistanceTo(Nodes[b].Point), NavEdge.Hop, both: true);
        }
        // Leaps: near-enough surfaces in the open air, validated by a simple clear line against tank air.
        for (int i = 0; i < Nodes.Count; i++)
        {
            for (int j = i + 1; j < Nodes.Count; j++)
            {
                if (Nodes[i].LoopId == Nodes[j].LoopId) continue;
                double d = Nodes[i].Point.DistanceTo(Nodes[j].Point);
                if (d > LeapRange || d < 24) continue;
                var a = Nodes[i].Point; var b = Nodes[j].Point;
                if (b.Y < a.Y - 130) continue; // no long drop in a tank link graph
                AddEdge(i, j, 70 + (float)d * .45f, NavEdge.Leap, both: true);
            }
        }
        BuildMs = Environment.TickCount64 - started;
    }

    void AddTurn(int node)
    {
        AddEdgeState(node * 2, node * 2 + 1, TurnCost, NavEdge.Turn);
        AddEdgeState(node * 2 + 1, node * 2, TurnCost, NavEdge.Turn);
    }

    void AddEdge(int a, int b, float cost, NavEdge kind, bool both = false)
    {
        AddEdgeState(a * 2, b * 2, cost, kind);
        AddEdgeState(b * 2, a * 2, cost, kind);
        if (both)
        {
            AddEdgeState(a * 2 + 1, b * 2 + 1, cost, kind);
            AddEdgeState(b * 2 + 1, a * 2 + 1, cost, kind);
        }
    }

    void AddEdgeState(int a, int b, float cost, NavEdge kind)
    {
        if (!_graph.TryGetValue(a, out var list)) _graph[a] = list = new();
        list.Add((b, cost, kind));
    }

    int NearestNode(string loopId, V2 at, double within)
    {
        if (!_byLoop.TryGetValue(loopId, out var ids) || ids.Count == 0) return -1;
        int best = -1; double bd = within * within;
        foreach (var i in ids) { double d = Nodes[i].Point.DistanceSquaredTo(at); if (d < bd) { bd = d; best = i; } }
        return best;
    }

    public Spot? Nearest(V2 p, string? loopId = null)
    {
        Spot? best = null; double bd = double.MaxValue;
        foreach (var s in Nodes)
        {
            if (loopId is not null && s.LoopId != loopId) continue;
            double d = s.Point.DistanceSquaredTo(p);
            if (d < bd) { bd = d; best = s; }
        }
        return best;
    }

    int StartState(Spot s, int dir)
    {
        int idx = Nodes.FindIndex(n => n.LoopId == s.LoopId && n.SegIdx == s.SegIdx && Math.Abs(n.Anchor.T - s.Anchor.T) < .01);
        if (idx < 0) idx = 0;
        return idx * 2 + (dir < 0 ? 1 : 0);
    }

    public List<Spot>? Path(V2 from, V2 to, int dir = 1)
    {
        var start = Nearest(from);
        var goal = Nearest(to);
        if (start is null || goal is null) return null;
        int startState = StartState(start.Value, dir);
        int goalNode = Nodes.FindIndex(n => n.LoopId == goal.Value.LoopId && n.SegIdx == goal.Value.SegIdx && Math.Abs(n.Anchor.T - goal.Value.Anchor.T) < .01);
        if (goalNode < 0) return null;
        var open = new PriorityQueue<int, float>();
        var g = new Dictionary<int, float> { [startState] = 0 };
        var prev = new Dictionary<int, (int from, NavEdge kind)>();
        open.Enqueue(startState, 0);
        int found = -1;
        while (open.TryDequeue(out int state, out float _))
        {
            int node = state / 2;
            if (node == goalNode) { found = state; break; }
            if (!_graph.TryGetValue(state, out var edges)) continue;
            foreach (var (next, cost, kind) in edges)
            {
                float ng = g[state] + cost;
                if (g.TryGetValue(next, out var old) && old <= ng) continue;
                g[next] = ng;
                prev[next] = (state, kind);
                float h = (float)Nodes[next / 2].Point.DistanceTo(goal.Value.Point);
                open.Enqueue(next, ng + h);
            }
        }
        if (found < 0) return null;
        var states = new List<int>();
        for (int s = found; ; s = prev[s].from)
        {
            states.Add(s);
            if (s == startState) break;
            if (!prev.ContainsKey(s)) return null;
        }
        states.Reverse();
        return states.Select(s => Nodes[s / 2]).DistinctBy(s => (s.LoopId, s.SegIdx, Math.Round(s.Anchor.T, 1))).ToList();
    }

    public bool Reachable(V2 from, V2 to)
    {
        if (Nodes.Count == 0) return false;
        var a = Nearest(from); var b = Nearest(to);
        if (a is null || b is null) return false;
        // Floyd-free closure from the start state, good enough for the survey and tests.
        var seen = new HashSet<int>();
        var stack = new Stack<int>();
        int start = StartState(a.Value, 1);
        stack.Push(start); seen.Add(start);
        while (stack.Count > 0)
        {
            int s = stack.Pop();
            if (Nodes[s / 2].LoopId == b.Value.LoopId) return true;
            if (!_graph.TryGetValue(s, out var edges)) continue;
            foreach (var e in edges) if (seen.Add(e.to)) stack.Push(e.to);
        }
        return false;
    }

    public int ReachableSpotCount(V2 from)
    {
        var a = Nearest(from);
        if (a is null) return 0;
        var seen = new HashSet<int>();
        var stack = new Stack<int>();
        int start = StartState(a.Value, 1);
        stack.Push(start); seen.Add(start);
        var loops = new HashSet<string>();
        while (stack.Count > 0)
        {
            int s = stack.Pop();
            loops.Add(Nodes[s / 2].LoopId);
            if (!_graph.TryGetValue(s, out var edges)) continue;
            foreach (var e in edges) if (seen.Add(e.to)) stack.Push(e.to);
        }
        return loops.Count;
    }
}

/// <summary>A small errand machine: chooses a tank place for a use and walks there.</summary>
public enum ErrandUse { Drink, Shelter, Hide, Lookout, Sleep, Rest, Bask, WarmUp, Dew, Ambush, Forage, Emerge, Shade, Rounds }

public sealed class HabitatErrand
{
    public ErrandUse Use;
    public InteractionPoint? Point;
    public Anchor Anchor;
    public V2 Target;
    public string Description = "";
}

public static class HabitatErrands
{
    public static HabitatErrand? Choose(HabitatWorld world, HabitatKnowledge knowledge, Spider spider, WeatherConditions weather, Rng rng)
    {
        var options = new List<(double weight, HabitatErrand errand)>();
        foreach (var it in world.Items)
        {
            var points = HabitatInteractions.Points(it, spider.Map);
            foreach (var p in points)
            {
                if (p.Stand is not { } stand) continue;
                double w = 0;
                switch (p.Kind)
                {
                    case InteractionKind.DrinkEdge when it.Water() is not null: w = 6; break;
                    case InteractionKind.Interior: w = weather.Mix.Rain > .2 ? 8 : 2.2; break;
                    case InteractionKind.Top when it.Kind.ClimableSafe(): w = 1.2 + (it.Y > 100 ? 1.8 : 0); break;
                    case InteractionKind.Bask when weather.Mix.Sun > .3: w = 7 * weather.Mix.Sun; break;
                    case InteractionKind.Lookout: w = 2.4; break;
                    case InteractionKind.SilkAnchor: w = .5; break;
                }
                if (w > 0)
                {
                    w *= 1 + Math.Max(-.5, knowledge.For(it.Uid).Fond * .6);
                    options.Add((w, new HabitatErrand
                    {
                        Use = p.Kind == InteractionKind.DrinkEdge ? ErrandUse.Drink : p.Kind == InteractionKind.Bask ? ErrandUse.Bask : p.Kind == InteractionKind.Lookout ? ErrandUse.Lookout : ErrandUse.Shelter,
                        Point = p, Anchor = stand.Anchor, Target = p.StandPoint ?? p.Point, Description = $"{p.Kind} the {it.Kind.Label()}"
                    }));
                }
            }
        }
        if (options.Count == 0) return null;
        int i = rng.WeightedIndex(options.Select(o => o.weight).ToList());
        return options[Math.Clamp(i, 0, options.Count - 1)].errand;
    }
}

static class HabitatKindNavCompat
{
    public static bool ClimableSafe(this HabitatItemKind kind) => kind.Climbable();
}
