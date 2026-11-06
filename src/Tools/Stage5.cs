using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

public static class Stage5
{
    static void BodyLanguageChecks()
    {
        var s = new Spider(new SpiderDesign(), new SurfaceMap());
        s.Nod(1);
        for (int i = 0; i < 12; i++) s.Update(1.0 / 60);
        Harness.Check(s.BuildPose().HeadTilt < -0.25, "curt nod dips head");
        for (int i = 0; i < 20; i++) s.Update(1.0 / 60);
        Harness.Near(s.BuildPose().HeadTilt, 0, 1e-9, "nod ends cleanly");
        // Isolate the deliberate blink from the independent randomized idle blink timer.
        s.BlinkTimer = 100;
        s.SlowBlink(0.5);
        s.Update(1.0 / 60);
        Harness.Check(s.BuildPose().Blink < 0.1, "delayed slow blink waits");
        for (int i = 0; i < 65; i++) s.Update(1.0 / 60);
        Harness.Near(s.BuildPose().Blink, 1, 0.01, "slow blink holds eyes shut");
        for (int i = 0; i < 60; i++) s.Update(1.0 / 60);
        Harness.Check(s.BuildPose().Blink < 0.1, "slow blink opens again");
        s.ShakeHead();
        double biggest = 0;
        for (int i = 0; i < 60; i++) { s.Update(1.0 / 60); biggest = Math.Max(biggest, Math.Abs(s.BuildPose().HeadTurn)); }
        Harness.Check(biggest > 0.1, "head shake turns side to side");
        Harness.Near(s.BuildPose().HeadTurn, 0, 1e-9, "head shake ends cleanly");
    }

    static void InputChecks()
    {
        var s = new Spider(new SpiderDesign(), new SurfaceMap());
        var input = new SpiderPointerInput(s);
        Harness.Check(!input.Down(new V2(1000, 1000), 0), "input outside spider passes through");
        Harness.Check(input.Down(s.Pos, 1), "mouse press captures spider");
        input.Drag(new V2(100, 0), 1.05);
        input.Up(new V2(200, 0), 1.1);
        Harness.Near(s.Velocity.X, 2000, 1e-8, "quick flick uses recent pointer velocity");
        input.Down(s.Pos, 2);
        for (int i = 1; i <= 8; i++) input.Drag(s.Pos + new V2(i * 10, 0), 2 + i * 0.1);
        input.Up(s.Pos + new V2(90, 0), 2.9);
        Harness.Near(s.Velocity.X, 100, 1e-8, "long drag uses recent sample rather than whole gesture");
        int greeted = 0;
        s.PointerRemembered += e => { if (e == PointerMemoryEvent.Greeted) greeted++; };
        input.Down(s.Pos, 3);
        input.Up(s.Pos, 3.1);
        Harness.Check(greeted == 1, "short stationary press becomes poke on release");
        s.Mode = Mode.Attached;
        input.Down(s.Pos, 4, clickCount: 2);
        Harness.Check(!s.IsHeld && s.Activity is Activity.Bounce or Activity.Dance, "double-click celebrates rather than grabbing");
        input.Down(s.Pos, 5);
        input.Cancel();
        Harness.Check(!s.IsHeld && s.RescueLineRequested, "lost capture safely releases with rescue request");
    }

    static void GrabChecks()
    {
        var map = Synth.Build(Synth.Desktop().With(Synth.Window(1, 200, 200, 600, 400)));
        var s = new Spider(new SpiderDesign(), map);
        s.SetAnchor("win:1", 0, 150, 1);
        V2 origin = s.Pos;
        V2 grab = origin + new V2(5, 4);
        s.BeginGrab(grab);
        Harness.Check(s.IsHeld && s.Activity == Activity.Idle, "grab enters held mode and cancels activity");
        Harness.Near(s.Grasped.Velocity, 6, 0, "grab applies reference grasp impulse");
        Harness.Near(s.Startled.Velocity, 9, 0, "grab applies reference startle impulse");
        s.Update(1.0 / 60);
        Harness.Check(s.BuildPose().Emote == EmoteKind.Surprise && s.BuildPose().EmoteT > 0, "grab surprise reaches existing emote renderer");
        Harness.Near(s.Pos.DistanceTo(origin), 0, 1e-8, "grab preserves pointer offset");
        s.MoveGrab(grab + new V2(200, 100));
        s.Update(1.0 / 60);
        Harness.Check(s.Pos.X > origin.X + 100 && s.Pos.X < origin.X + 200, "held body follows nearly rigidly without snapping");
        for (int i = 0; i < 20; i++) s.Update(1.0 / 60);
        Harness.Near(s.Pos.DistanceTo(origin + new V2(200, 100)), 0, 0.01, "held body converges without snapping back to anchor");
        Harness.Check(!s.PointerNameVisible, "name hidden while held");
        var pose = s.BuildPose();
        Harness.Check(pose.Legs.All(l => l.Foot.IsFinite), "held curled legs remain finite");
        V2 foot = pose.Legs[0].Foot;
        s.Update(1.0 / 60);
        Harness.Check(s.BuildPose().Legs[0].Foot.DistanceTo(foot) > 0, "held legs kick with time");
        var memories = new List<PointerMemoryEvent>();
        s.PointerRemembered += memories.Add;
        s.EndGrab(new V2(6000, 8000));
        Harness.Near(s.Velocity.Length, 2700, 1e-8, "throw capped at 2700");
        Harness.Check(s.Mode == Mode.Air && s.Air == AirKind.Thrown, "release enters thrown free flight");
        Harness.Check(!s.RescueLineRequested && memories.Last() == PointerMemoryEvent.Thrown, "hard throw flies and remembers thrown");
        Harness.Near(s.NoAttachFor, 0.06, 1e-9, "release prevents immediate reattachment");
        V2 released = s.Pos;
        s.Update(1.0 / 60);
        Harness.Check(s.Pos.X > released.X && s.Velocity.Y < 2160, "flight advances with gravity and drag, not old anchor");
        s.BeginGrab(s.Pos);
        s.EndGrab(new V2(100, 20));
        Harness.Check(s.RescueLineRequested && memories.Last() == PointerMemoryEvent.Carried, "soft toss requests rescue line and remembers carried");
        int count = memories.Count;
        s.EndGrab(V2.Zero);
        Harness.Check(memories.Count == count, "duplicate release ignored");
    }

    static void CelebrationChecks()
    {
        for (ulong seed = 1; seed <= 12; seed++)
        {
            var s = new Spider(new SpiderDesign(), new SurfaceMap(), new Rng(seed));
            s.Celebrate();
            Activity next = s.Activity == Activity.Bounce ? Activity.Wiggle : Activity.ArmsUp;
            Harness.Check(s.Activity is Activity.Bounce or Activity.Dance, $"celebration {seed}: happy opening");
            for (int i = 0; i < 105; i++) s.Update(1.0 / 60);
            Harness.Check(s.Activity == next, $"celebration {seed}: queued follow-through");
        }
    }

    static void WatchingChecks()
    {
        var map = Synth.Build(Synth.Desktop().With(Synth.Window(1, 200, 200, 700, 400)));
        var s = new Spider(new SpiderDesign(), map, new Rng(7));
        s.SetAnchor("win:1", 0, 200, 1);
        s.SetCursor(s.Pos + new V2(120, 20));
        for (int i = 0; i < 60; i++) s.Update(1.0 / 60);
        Harness.Check(s.Interest > 0.85, "a pointer hanging about builds interest");
        // Off to the side and above: the head goes further round than the legs do (spec 5.5).
        s.SetCursor(s.Pos + new V2(-50, 55));
        for (int i = 0; i < 20; i++) s.Update(1.0 / 60);
        Harness.Check(s.BuildPose().HeadTurn < -0.25, "head turns toward an off-axis pointer");
        s.SetCursor(s.Pos + new V2(120, 20));
        for (int i = 0; i < 120; i++) s.Update(1.0 / 60);

        // Coming round the far side: the body follows continuously, through the front view.
        s.SetCursor(s.Pos + new V2(-120, 20));
        for (int i = 0; i < 140; i++) s.Update(1.0 / 60);
        Harness.Check(s.InterestSide < 0 && s.Facing < -0.5, "body comes round to a pointer behind it");

        // Straight overhead keeps the side it had — no flicker between mirrors.
        double side = Math.Sign(s.Facing);
        s.SetCursor(s.Pos + new V2(2, 90));
        for (int i = 0; i < 60; i++) s.Update(1.0 / 60);
        Harness.Check(Math.Sign(s.Facing) == side, "pointer overhead never flips the body");

        // Watch the Cursor off: no interest, no head turn.
        var off = new Spider(new SpiderDesign(), map, new Rng(8));
        off.SetAnchor("win:1", 0, 200, 1);
        off.FollowCursor = false;
        off.SetCursor(off.Pos + new V2(60, 10));
        for (int i = 0; i < 60; i++) off.Update(1.0 / 60);
        Harness.Check(off.Interest < 0.05, "Watch the Cursor off leaves it alone");

        // A whip across its face: one startled hop on the spot, not a run.
        var w = new Spider(new SpiderDesign(), map, new Rng(9));
        w.SetAnchor("win:1", 0, 200, 1);
        w.SetCursor(w.Pos + new V2(70, 0));
        w.Update(1.0 / 60);
        w.SetCursor(w.Pos + new V2(-70, 4));
        w.Update(1.0 / 60);
        Harness.Check(w.Activity == Activity.Hop, "a whipped pointer makes it hop");
        Harness.Check(w.Mode == Mode.Attached, "a pointer whip does not make it run");

        // Stroking: back and forth on top of it, at stroking pace.
        var p = new Spider(new SpiderDesign(), map, new Rng(10));
        p.SetAnchor("win:1", 0, 200, 1);
        int stroked = 0;
        p.PointerRemembered += e => { if (e == PointerMemoryEvent.Stroked) stroked++; };
        double dir = 1;
        for (int i = 0; i < 90; i++)
        {
            p.SetCursor(p.Pos + new V2(dir * 6, 2));
            dir = -dir;
            p.Update(1.0 / 60);
        }
        Harness.Check(p.PettingScore > 0.85, "stroking builds a petting score");
        Harness.Check(stroked > 0 && p.Happy.Value > 0.5, "a stroke makes it happy and remembers it");

        // Fidget close by: stalk, pounce, cling, then shake it off.
        var h = new Spider(new SpiderDesign(), map, new Rng(11));
        h.SetAnchor("win:1", 0, 200, 1);
        // The reference will not hunt in its first eight seconds, and a parked pointer is old news:
        // keep it moving gently while the cooldown runs.
        for (int i = 0; i < 600; i++)
        {
            h.SetCursor(h.Pos + new V2(62 + Math.Sin(i * 0.6) * 0.5, 8));
            h.Update(1.0 / 60);
        }
        Harness.Check(h.Interest > 0.5, "a moving pointer holds interest past the hunt cooldown");
        dir = 1;
        for (int i = 0; i < 400 && h.Hunt == CursorHunt.None; i++)
        {
            h.SetCursor(h.Pos + new V2(60 + dir * 16, 8));
            dir = -dir;
            h.Update(1.0 / 60);
        }
        Harness.Check(h.Hunt == CursorHunt.Stalking, "a fidgeting pointer is stalked");
        bool sprang = false, hooked = false;
        for (int i = 0; i < 200; i++)
        {
            h.Update(1.0 / 60);
            if (h.Hunt == CursorHunt.Pouncing) sprang = true;
            if (h.Hunt == CursorHunt.Clinging) { hooked = true; break; }
        }
        Harness.Check(sprang, "the stalk springs at the pointer");
        Harness.Check(hooked, "the pounce takes hold of the pointer");
        Harness.Check(h.Mode == Mode.Clinging && !h.HitTest(h.Pos), "clicks pass through while clinging");
        for (int i = 0; i < 12; i++)
        {
            h.SetCursor(h.Pos + new V2(dir * 90, 0));
            dir = -dir;
            h.Update(1.0 / 60);
        }
        Harness.Check(h.Hunt == CursorHunt.None && h.Mode == Mode.Air, "shaking the pointer flings it off");
        Harness.Check(h.RescueLineRequested, "it drops away on a line");

        var no = new Spider(new SpiderDesign(), map, new Rng(12));
        no.SetAnchor("win:1", 0, 200, 1);
        no.PounceOnCursor = false;
        no.SetCursor(no.Pos + new V2(30, 2));
        for (int i = 0; i < 45; i++)
        {
            no.SetCursor(no.Pos + new V2(30 + dir * 8, 2));
            dir = -dir;
            no.Update(1.0 / 60);
        }
        Harness.Check(no.Hunt == CursorHunt.None, "Pounce on the Cursor off never hunts");
    }

    public static int Run(string[] args)
    {
        Harness.Section("stage 5 pointer foundations (partial acceptance)");
        var spider = new Spider(new SpiderDesign(), new SurfaceMap(), new Rng(42));
        spider.Pos = new V2(100, 100);
        foreach (double scale in new[] { 0.62, 0.78, 0.95, 1.2, 1.55 })
        {
            spider.UserScale = scale;
            Harness.Check(spider.HitTest(spider.Pos + new V2(30 * scale, 0)), $"scale {scale}: grab boundary hits");
            Harness.Check(!spider.HitTest(spider.Pos + new V2(30 * scale + 0.01, 0)), $"scale {scale}: outside passes through");
        }
        spider.ClickToPickUp = false;
        Harness.Check(!spider.HitTest(spider.Pos), "disabled pickup passes through the body");
        spider.ClickToPickUp = true;
        spider.SetCursor(spider.Pos);
        for (int i = 0; i < 45; i++) spider.Update(1.0 / 60);
        Harness.Check(spider.PointerNameVisible, "stationary hover reveals name after 0.7 s");
        spider.SetCursor(spider.Pos + new V2(300, 0));
        spider.Update(1.0 / 60);
        Harness.Check(!spider.PointerNameVisible, "leaving body clears hover");

        var orders = new List<PointerLineOrder>();
        spider.ScrollOrdered += orders.Add;
        spider.Scroll(3, startsGesture: true);
        Harness.Check(orders.Count == 0, "precise scroll waits for four points");
        spider.Scroll(1);
        spider.Scroll(20);
        Harness.Check(orders.SequenceEqual(new[] { PointerLineOrder.Up }), "one swipe gives one order");
        spider.Scroll(-30);
        Harness.Check(orders.Last() == PointerLineOrder.Down && orders.Count == 2, "reversed accumulated swipe gives opposite order");
        spider.Scroll(0.49, precise: false, startsGesture: true);
        Harness.Check(orders.Count == 2, "wheel waits for half a line");
        spider.Scroll(0.01, precise: false);
        Harness.Check(orders.Count == 3, "half a wheel line gives order");
        for (int i = 0; i < 22; i++) spider.Update(1.0 / 60);
        spider.Scroll(0.5, precise: false);
        Harness.Check(orders.Count == 4, "pause starts fresh gesture");

        int greeted = 0, menus = 0;
        spider.PointerRemembered += _ => greeted++;
        spider.ContextMenuRequested += () => menus++;
        spider.RightClick();
        Harness.Check(menus == 1, "right-click requests host menu");
        for (int i = 0; i < 100; i++) spider.Poke();
        Harness.Check(greeted == 100, "every poke emits greeted memory event");
        Harness.Near(spider.Stretch.Velocity, -5, 0, "poke gives specified stretch impulse");
        Harness.Check(spider.ActivityDur >= 0.55 && spider.ActivityDur <= 4.4, "poke reaction duration is in reference range");
        BodyLanguageChecks();
        InputChecks();
        GrabChecks();
        CelebrationChecks();
        WatchingChecks();
        return Harness.Summarise("stage 5 pointer foundations; not full stage acceptance");
    }
}
