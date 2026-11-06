using System.Diagnostics;
using SpiderBuddy.Core;
using SpiderBuddy.Renderer;

namespace SpiderBuddy.App;

/// <summary>In-process Stage 20 host checks: the real WinForms app, map, renderer and panel.</summary>
public static class Stage20Smoke
{
    static int _failed;

    public static async Task<int> Run(SpiderApplicationContext app)
    {
        _failed = 0;
        Program.SmokeLog("stage20-smoke: app and map");
        Check(app.AppVersion.Length > 0, "the app reports its version");
        Check(app.Spider.Map.LoopCount > 0, "the live app has walkable desktop loops");
        Check(app.Spider.UserScale > 0, "the live app has a size scale");

        Program.SmokeLog("stage20-smoke: pose and renderer");
        var pose = app.Spider.BuildPose();
        using (var sprite = SpriteRaster.Render(pose, app.Spider.Design.Look, app.Spider.UserScale))
        {
            Check(sprite.Width >= 100 && sprite.Height == sprite.Width,
                "the sprite raster has the expected square size", $"{sprite.Width}px");
            Check(sprite.Width >= (int)Math.Round(SpiderRenderer.DrawRadius * 2 * app.Spider.UserScale) - 1,
                "the sprite is large enough for drawRadius");
        }

        Program.SmokeLog("stage20-smoke: a short live step");
        bool finite = true;
        for (int i = 0; i < 120; i++)
        {
            app.Spider.Update(1.0 / 60);
            finite &= double.IsFinite(app.Spider.Pos.X) && double.IsFinite(app.Spider.Pos.Y);
        }
        Check(finite, "the live spider survives two simulated seconds");

        Program.SmokeLog("stage20-smoke: panel");
        app.ShowPanel();
        await Task.Delay(250);
        Check(app.PanelPageHasText(0, "Spider Buddy") || app.PanelPageHasText(0, "Mochi"),
            "page 1 is populated");
        app.HidePanel();

        Program.SmokeLog("stage20-smoke: bundled extension");
        string extension = Path.Combine(AppContext.BaseDirectory, "Extension");
        Check(File.Exists(Path.Combine(extension, "manifest.json")),
            "the browser extension is next to the app");
        Check(File.Exists(Path.Combine(extension, "worker.js")),
            "the extension worker is bundled");

        return _failed;
    }

    static void Check(bool ok, string what, string? detail = null)
    {
        if (!ok) _failed++;
        string line = (ok ? "[ok] " : "[FAIL] ") + what + (ok || detail is null ? "" : " — " + detail);
        Program.SmokeLog("stage20-smoke: " + line);
        Console.WriteLine(line);
    }
}
