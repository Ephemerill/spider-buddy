using System.Diagnostics;
using SpiderBuddy.Core;

namespace SpiderBuddy.App;

/// <summary>
/// Optional app test hooks (spec 20): SPIDER_FRAMES is a once-a-second frame meter,
/// SPIDER_TIMING adds the update/draw phase split, SPIDER_STATS prints a final process
/// snapshot, and SPIDER_OPEN_TIMING records startup. They are inert unless requested.
/// </summary>
public static class FrameStats
{
    public static readonly bool Frames = Environment.GetEnvironmentVariable("SPIDER_FRAMES") == "1";
    public static readonly bool Timing = Environment.GetEnvironmentVariable("SPIDER_TIMING") == "1";
    public static readonly bool Stats = Environment.GetEnvironmentVariable("SPIDER_STATS") == "1";
    public static readonly bool OpenTiming = Environment.GetEnvironmentVariable("SPIDER_OPEN_TIMING") == "1";
    public static bool Enabled => Frames || Timing;

    static long _windowStart;
    static int _frames;
    static double _busySum, _busyWorst, _updateSum, _drawSum, _longestGap;
    static int _over12;
    static long _totalFrames;
    static double _totalBusy;

    public static void Record(double busyMs, double updateMs, double drawMs, double gapMs)
    {
        if (!Enabled) return;
        if (_windowStart == 0) _windowStart = Stopwatch.GetTimestamp();
        _frames++;
        _totalFrames++;
        _busySum += busyMs;
        _totalBusy += busyMs;
        _busyWorst = Math.Max(_busyWorst, busyMs);
        _updateSum += updateMs;
        _drawSum += drawMs;
        _longestGap = Math.Max(_longestGap, gapMs);
        if (busyMs > 12) _over12++;

        double seconds = (Stopwatch.GetTimestamp() - _windowStart) / (double)Stopwatch.Frequency;
        if (seconds < 1.0) return;
        double fps = _frames / seconds;
        string line = Frames
            ? $"frames {fps:0.0}/s busy {_busySum / _frames:0.00} ms mean {_busyWorst:0.00} ms worst " +
              $"{_over12} >12ms longest-gap {_longestGap:0.0} ms"
            : $"timing update {_updateSum / _frames:0.00} ms draw {_drawSum / _frames:0.00} ms " +
              $"busy {_busySum / _frames:0.00} ms worst {_busyWorst:0.00} ms";
        Program.SmokeLog("meter: " + line);
        Console.WriteLine(line);
        _windowStart = Stopwatch.GetTimestamp();
        _frames = 0;
        _busySum = _busyWorst = _updateSum = _drawSum = _longestGap = 0;
        _over12 = 0;
    }

    public static void ReportStats(Spider? spider = null)
    {
        if (!Stats && !Frames && !Timing) return;
        long working = Environment.WorkingSet;
        long managed = GC.GetTotalMemory(false);
        string spiderText = spider is null
            ? ""
            : $" activity={spider.Activity} mode={spider.Mode} pos={spider.Pos.X:0.0},{spider.Pos.Y:0.0}";
        Program.SmokeLog($"stats: frames={_totalFrames} busy-mean={(_totalFrames == 0 ? 0 : _totalBusy / _totalFrames):0.00}ms " +
                         $"working={working / (1024.0 * 1024):0.0}MB managed={managed / (1024.0 * 1024):0.0}MB{spiderText}");
    }
}
