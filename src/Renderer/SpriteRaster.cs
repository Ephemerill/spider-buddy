using SkiaSharp;
using SpiderBuddy.Core;

namespace SpiderBuddy.Renderer;

/// <summary>
/// Rasterises the sprite into an 8-bit sRGB bitmap (spec 3.3). The image is drawn off the main
/// thread and shown at its own size, centred, never stretched.
/// </summary>
public static class SpriteRaster
{
    /// <summary>Window slack of 68 units around the sprite (spec 3.1).</summary>
    public const double WindowSlack = 68;

    /// <summary>spriteSide = max(100, round(72·2·scale)) — the sprite draws within radius 72.</summary>
    public static double SpriteSide(double scale) => Math.Max(100, Math.Round(SpiderRenderer.DrawRadius * 2 * scale));

    public static SKImageInfo Info(double scale)
    {
        int side = (int)Math.Ceiling(SpriteSide(scale));
        return new SKImageInfo(side, side, SKColorType.Bgra8888, SKAlphaType.Premul, SKColorSpace.CreateSrgb());
    }

    /// <summary>
    /// Draw a pose centred in its own sprite bitmap. The pose position is ignored; only the
    /// body-local drawing is used, so the layer can be moved without redrawing.
    /// </summary>
    public static SKBitmap Render(SpiderPose pose, SpiderLook look, double scale)
    {
        var info = Info(scale);
        var bmp = new SKBitmap(info);
        using (var canvas = new SKCanvas(bmp))
        {
            canvas.Clear(SKColors.Transparent);
            var local = pose.Clone();
            local.Pos = new V2(info.Width / 2.0, info.Height / 2.0);
            local.Scale = scale;
            var draw = new SkiaDraw(canvas);
            // Skia is y-down; the core's world is y-up. Translate the origin
            // to the bottom before flipping, or the whole sprite draws above
            // the bitmap and comes out empty.
            canvas.Translate(0, info.Height);
            canvas.Scale(1, -1);
            SpiderRenderer.Draw(draw, local, look, drawNameTag: false);
        }
        return bmp;
    }

    /// <summary>
    /// The draw-radius check (spec 3.3): the furthest drawn pixel from the body centre across a
    /// pose, in body units. Must stay inside <see cref="SpiderRenderer.DrawRadius"/>.
    /// </summary>
    public static (double radius, SKBitmap bitmap) Measure(SpiderPose pose, SpiderLook look)
    {
        const double scale = 1.0;
        var info = Info(scale);
        var bmp = new SKBitmap(info);
        using (var canvas = new SKCanvas(bmp))
        {
            canvas.Clear(SKColors.Transparent);
            var local = pose.Clone();
            local.Pos = new V2(info.Width / 2.0, info.Height / 2.0);
            local.Scale = scale;
            var draw = new SkiaDraw(canvas);
            canvas.Translate(0, info.Height);
            canvas.Scale(1, -1);
            SpiderRenderer.Draw(draw, local, look, drawNameTag: false);
        }

        double cx = info.Width / 2.0, cy = info.Height / 2.0;
        double maxR = 0;
        for (int y = 0; y < info.Height; y++)
        {
            for (int x = 0; x < info.Width; x++)
            {
                // premultiplied BGRA; any alpha at all means something was drawn here
                var c = bmp.GetPixel(x, y);
                if (c.Alpha == 0) continue;
                double dx = x + 0.5 - cx, dy = y + 0.5 - cy;
                double r = Math.Sqrt(dx * dx + dy * dy);
                if (r > maxR) maxR = r;
            }
        }
        return (maxR, bmp);
    }
}
