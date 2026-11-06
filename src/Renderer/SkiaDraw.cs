using SkiaSharp;
using SpiderBuddy.Core;

namespace SpiderBuddy.Renderer;

/// <summary>
/// A small 2-D vector API implemented over Skia, matching the ~40 CoreGraphics verbs the art uses
/// (spec 3.2, decision D3). Skia gives identical anti-aliasing on every platform, so output can be
/// compared against the macOS build.
/// </summary>
public sealed class SkiaDraw : IDraw
{
    readonly SKCanvas _canvas;
    readonly SKPaint _paint = new() { IsAntialias = true };
    SKPath _path = new();

    public SKCanvas Canvas => _canvas;

    public SkiaDraw(SKCanvas canvas)
    {
        _canvas = canvas;
    }

    static SKColor Col(Rgba c) => new(
        (byte)M.Clamp(c.R * 255, 0, 255),
        (byte)M.Clamp(c.G * 255, 0, 255),
        (byte)M.Clamp(c.B * 255, 0, 255),
        (byte)M.Clamp(c.A * 255, 0, 255));

    // ---------------------------------------------------------------- state

    public void Save() => _canvas.Save();

    public void Restore() => _canvas.Restore();

    public void Translate(double x, double y) => _canvas.Translate((float)x, (float)y);

    public void Rotate(double radians) => _canvas.RotateRadians((float)radians);

    public void Scale(double x, double y) => _canvas.Scale((float)x, (float)y);

    public void SetFill(Rgba c) { _paint.Style = SKPaintStyle.Fill; _paint.Color = Col(c); }

    public void SetStroke(Rgba c) { _paint.Style = SKPaintStyle.Stroke; _paint.Color = Col(c); }

    public void SetLineWidth(double w) => _paint.StrokeWidth = (float)w;

    public void SetAlpha(double a) => _paint.Color = _paint.Color.WithAlpha((byte)M.Clamp(a * 255, 0, 255));

    public void SetLineCap(LineCap cap) => _paint.StrokeCap = cap switch
    {
        LineCap.Round => SKStrokeCap.Round,
        LineCap.Square => SKStrokeCap.Square,
        _ => SKStrokeCap.Butt
    };

    public void SetLineJoin(LineJoin join) => _paint.StrokeJoin = join switch
    {
        LineJoin.Round => SKStrokeJoin.Round,
        LineJoin.Bevel => SKStrokeJoin.Bevel,
        _ => SKStrokeJoin.Miter
    };

    // ---------------------------------------------------------------- paths

    public void NewPath()
    {
        _path.Reset();
    }

    public void MoveTo(V2 p) => _path.MoveTo((float)p.X, (float)p.Y);

    public void LineTo(V2 p) => _path.LineTo((float)p.X, (float)p.Y);

    public void QuadTo(V2 control, V2 p) => _path.QuadTo((float)control.X, (float)control.Y, (float)p.X, (float)p.Y);

    public void CurveTo(V2 c1, V2 c2, V2 p) =>
        _path.CubicTo((float)c1.X, (float)c1.Y, (float)c2.X, (float)c2.Y, (float)p.X, (float)p.Y);

    public void ArcTo(V2 centre, double radius, double startAngle, double endAngle, bool clockwise)
    {
        var rect = new SKRect((float)(centre.X - radius), (float)(centre.Y - radius),
                              (float)(centre.X + radius), (float)(centre.Y + radius));
        float sweep = (float)((endAngle - startAngle) * 180 / Math.PI);
        if (sweep < 0) sweep += 360;
        _path.ArcTo(rect, (float)(startAngle * 180 / Math.PI), sweep, false);
    }

    public void ClosePath() => _path.Close();

    public void AddEllipse(V2 c, double rx, double ry) =>
        _path.AddOval(new SKRect((float)(c.X - rx), (float)(c.Y - ry), (float)(c.X + rx), (float)(c.Y + ry)));

    public void AddRect(Rect r) =>
        _path.AddRect(new SKRect((float)r.MinX, (float)r.MinY, (float)r.MaxX, (float)r.MaxY));

    public void AddRoundedRect(Rect r, double radius) =>
        _path.AddRoundRect(new SKRect((float)r.MinX, (float)r.MinY, (float)r.MaxX, (float)r.MaxY),
                           (float)radius, (float)radius);

    // ---------------------------------------------------------------- paint

    public void Fill() => _canvas.DrawPath(_path, _paint.WithStyleFill());

    public void Stroke() => _canvas.DrawPath(_path, _paint.WithStyleStroke());

    public void FillAndStroke() => _canvas.DrawPath(_path, _paint);

    public void FillEllipse(V2 c, double rx, double ry)
    {
        var r = new SKRect((float)(c.X - rx), (float)(c.Y - ry), (float)(c.X + rx), (float)(c.Y + ry));
        _canvas.DrawOval(r, _paint.WithStyleFill());
    }

    public void StrokeEllipse(V2 c, double rx, double ry)
    {
        var r = new SKRect((float)(c.X - rx), (float)(c.Y - ry), (float)(c.X + rx), (float)(c.Y + ry));
        _canvas.DrawOval(r, _paint.WithStyleStroke());
    }

    // ---------------------------------------------------------------- clipping

    public void ClipRect(Rect r) =>
        _canvas.ClipRect(new SKRect((float)r.MinX, (float)r.MinY, (float)r.MaxX, (float)r.MaxY));

    public void ClipPath(bool evenOdd = false) =>
        _canvas.ClipPath(_path, evenOdd ? SKClipOperation.Difference : SKClipOperation.Intersect, true);

    // ---------------------------------------------------------------- gradients

    public void FillLinearGradient(V2 from, V2 to, Rgba a, Rgba b)
    {
        using var shader = SKShader.CreateLinearGradient(
            new SKPoint((float)from.X, (float)from.Y),
            new SKPoint((float)to.X, (float)to.Y),
            new[] { Col(a), Col(b) }, null, SKShaderTileMode.Clamp);
        using var p = new SKPaint { IsAntialias = true, Style = SKPaintStyle.Fill, Shader = shader };
        _canvas.DrawPath(_path, p);
    }

    public void FillRadialGradient(V2 centre, double radius, Rgba inner, Rgba outer)
    {
        using var shader = SKShader.CreateRadialGradient(
            new SKPoint((float)centre.X, (float)centre.Y), (float)radius,
            new[] { Col(inner), Col(outer) }, null, SKShaderTileMode.Clamp);
        using var p = new SKPaint { IsAntialias = true, Style = SKPaintStyle.Fill, Shader = shader };
        _canvas.DrawPath(_path, p);
    }

    public void DrawLine(V2 a, V2 b) =>
        _canvas.DrawLine((float)a.X, (float)a.Y, (float)b.X, (float)b.Y, _paint.WithStyleStroke());
}

static class PaintExt
{
    public static SKPaint WithStyleFill(this SKPaint p)
    {
        var c = p.Clone();
        c.Style = SKPaintStyle.Fill;
        return c;
    }

    public static SKPaint WithStyleStroke(this SKPaint p)
    {
        var c = p.Clone();
        c.Style = SKPaintStyle.Stroke;
        return c;
    }
}
