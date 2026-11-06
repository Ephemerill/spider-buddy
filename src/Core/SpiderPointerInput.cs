namespace SpiderBuddy.Core;

/// <summary>
/// Platform-independent version of OverlayWindow's mouse input rules. Host timestamps are seconds
/// from a monotonic clock; coordinates have already been converted to the spider's y-up world.
/// </summary>
public sealed class SpiderPointerInput
{
    readonly Spider _spider;
    readonly List<(V2 point, double time)> _samples = new(8);
    V2 _pressedAt;
    double _pressTime;
    bool _dragging;

    public SpiderPointerInput(Spider spider) => _spider = spider;

    /// <returns>Whether the input belongs to the spider (false means pass through).</returns>
    public bool Down(V2 point, double timestamp, int clickCount = 1)
    {
        if (!_spider.HitTest(point)) return false;
        _pressedAt = point;
        _pressTime = timestamp;
        _samples.Clear();
        _samples.Add((point, timestamp));
        _dragging = clickCount < 2;
        if (_dragging) _spider.BeginGrab(point);
        else _spider.Celebrate();
        return true;
    }

    public void Drag(V2 point, double timestamp)
    {
        if (!_dragging) return;
        _spider.MoveGrab(point);
        _samples.Add((point, timestamp));
        if (_samples.Count > 8) _samples.RemoveAt(0);
    }

    public void Up(V2 point, double timestamp)
    {
        if (!_dragging) return;
        _dragging = false;
        V2 velocity = V2.Zero;
        if (_samples.Count > 1)
        {
            var first = _samples[0];
            if (timestamp - first.time < 0.22)
                velocity = (point - first.point) / Math.Max(timestamp - first.time, 0.008);
            else
                for (int i = _samples.Count - 1; i >= 0; i--)
                    if (timestamp - _samples[i].time > 0.04)
                    {
                        velocity = (point - _samples[i].point) / Math.Max(timestamp - _samples[i].time, 0.008);
                        break;
                    }
        }
        _samples.Clear();
        if (point.DistanceTo(_pressedAt) < 4 && timestamp - _pressTime < 0.35)
        {
            _spider.EndGrab(V2.Zero);
            _spider.Poke();
        }
        else _spider.EndGrab(velocity);
    }

    /// <summary>Lost mouse capture releases safely rather than leaving a permanently held spider.</summary>
    public void Cancel()
    {
        if (_dragging) _spider.EndGrab(V2.Zero);
        _dragging = false;
        _samples.Clear();
    }
}
