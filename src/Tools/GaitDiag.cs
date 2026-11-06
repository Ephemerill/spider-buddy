using System;
using System.Collections.Generic;
using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

/// <summary>Frame-by-frame dump of the gait state, for diagnosing the leg machine.</summary>
public static class GaitDiag
{
    public static int Run(string[] args)
    {
        var desk = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "w", corner: 26));
        var map = Synth.Build(desk, 1.0);
        var spider = new Spider(Sheets.DefaultDesign(), map, new Rng(7)) { UserScale = 1.0 };
        spider.SetAnchor("win:1", 0, 20, 1);
        spider.Walk(1, 40);

        var prev = new V2[8];
        var wasStance = new bool[8];
        for (int i = 0; i < 8; i++) { spider.Update(1.0 / 60); prev[i] = spider.WorldFoot(i); wasStance[i] = !spider.Gait.Legs[i].InSwing; }

        var worst = new List<(double slide, int frame, int leg, double dTheta, double reach, bool clamp)>();

        for (int f = 0; f < 900; f++)
        {
            double beforeFacing = spider.Facing;
            spider.Update(1.0 / 60);
            for (int i = 0; i < 8; i++)
            {
                var foot = spider.WorldFoot(i);
                bool stance = !spider.Gait.Legs[i].InSwing;
                if (stance && wasStance[i] && foot.DistanceTo(prev[i]) > 1.0)
                {
                    var hip = SpiderRig.Rig(i, SpiderRig.ProfileAmount(spider.Facing), spider.Design.Look.Legs).Hip;
                    double reach = spider.Gait.Legs[i].Foot.DistanceTo(hip) / Math.Max(1e-6, spider.Gait.LegLen[i]);
                    worst.Add((foot.DistanceTo(prev[i]), f, i, spider.Gait.LastDTheta, reach,
                        spider.Facing != beforeFacing));
                }
                prev[i] = foot; wasStance[i] = stance;
            }
        }

        worst.Sort((a, b) => b.slide.CompareTo(a.slide));
        Console.WriteLine($"planted-foot moves over 1.0 units: {worst.Count}");
        for (int n = 0; n < Math.Min(12, worst.Count); n++)
        {
            var w = worst[n];
            Console.WriteLine($"  slide {w.slide:0.000}  frame {w.frame,4}  leg {w.leg}  dTheta {w.dTheta:0.0000}  reach {w.reach:0.000}  facingFlipped {w.clamp}");
        }
        return 0;
    }
}
