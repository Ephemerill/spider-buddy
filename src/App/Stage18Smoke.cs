using System.Net.WebSockets;
using System.Text;
using SpiderBuddy.Core;

namespace SpiderBuddy.App;

/// <summary>Live Stage 18 checks for the parts that need a real window, server and socket.</summary>
public static class Stage18Smoke
{
    static int _failed;

    public static async Task<int> Run(SpiderApplicationContext app)
    {
        _failed = 0;
        Program.SmokeLog("stage18-smoke: chat");
        bool wasIntelligence = app.Spider.Design.Intelligence;
        try
        {
            app.Spider.Design.Intelligence = true;
            app.OpenChat();
            await Task.Delay(300);
            Check(app.ChatOpen, "the chat pill opens");
            Check(app.Listening, "the spider listens while the pill is open");
            app.ChatForTest("hello");
            await Task.Delay(500);
            Check(app.LastThoughtText.Length > 0, "a hello gets an answer in the bubble");
            Check(app.ChatOpen, "the chat pill stays open for another line");
            app.CloseChat();
            await Task.Delay(150);
            Check(!app.ChatOpen, "Escape/clicking away closes the pill");
            Check(!app.Listening, "closing the pill releases the spider");
        }
        catch (Exception ex)
        {
            Check(false, "chat smoke completed: " + ex.GetType().Name + ": " + ex.Message);
        }
        finally
        {
            app.Spider.Design.Intelligence = wasIntelligence;
        }

        Program.SmokeLog("stage18-smoke: bridge");
        app.SetPageWatchForTest(true);
        Check(app.PageBridgeRunning, "the app starts its page bridge when climbing is switched on");
        app.SetPageWatchForTest(false);
        Check(!app.PageBridgeRunning, "the app stops its page bridge when climbing is switched off");
        Check(File.Exists(Path.Combine(AppContext.BaseDirectory, "Extension", "manifest.json")),
            "the browser extension is in the app's output folder");
        await Bridge();
        return _failed;
    }

    static async Task Bridge()
    {
        var bridge = new PageBridge();
        try
        {
            bridge.Start();
            Check(bridge.Running, "the loopback extension bridge listens");
            if (!bridge.Running) return;

            using var good = new ClientWebSocket();
            good.Options.SetRequestHeader("Origin", "chrome-extension://stage18-smoke");
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            await good.ConnectAsync(new Uri($"ws://127.0.0.1:{bridge.Port}/spider"), timeout.Token);
            Check(bridge.Connected, "a browser-extension origin completes the WebSocket handshake");
            string want = await Receive(good, timeout.Token);
            Check(want.Contains("\"want\""), "the app sends the windows it wants to climb");

            string layout = """
                {"type":"layout","tab":7,"window":{"left":0,"top":0,"width":1600,"height":900},
                 "view":{"w":1600,"h":900,"dpr":1},
                 "scrollers":[[0,-1,0,0,1600,900,0,0],[2,0,100,100,700,420,0,40]],
                 "fixed":[]}
                """;
            await Send(good, layout);
            await Task.Delay(300);
            Check(bridge.Pages.Count == 1, "layout is accepted from the extension");
            Check(bridge.Pages.FirstOrDefault()?.Tab == 7, "the layout keeps its tab number");
            Check(bridge.Pages.FirstOrDefault()?.Offsets.TryGetValue(2, out var first) == true && Math.Abs(first.Y - 40) < .01,
                "the layout keeps its scroll offsets");

            await Send(good, """{"type":"scroll","tab":7,"s":[[0,0,120],[2,0,75]]}""");
            await Task.Delay(300);
            var page = bridge.Pages.FirstOrDefault();
            Check(page?.Offsets.TryGetValue(2, out var scrolled) == true && Math.Abs(scrolled.Y - 75) < .01,
                "a scroll message updates the page's offsets");
            var vs = System.Windows.Forms.SystemInformation.VirtualScreen;
            var world = new Rect(-vs.Left, vs.Bottom - 900, 1600, 900);
            Check(bridge.PageIn(world) is not null,
                "the app can find the page by its window rectangle");

            using var bad = new ClientWebSocket();
            bad.Options.SetRequestHeader("Origin", "https://evil.example");
            bool refused = false;
            try
            {
                using var badTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
                await bad.ConnectAsync(new Uri($"ws://127.0.0.1:{bridge.Port}/spider"), badTimeout.Token);
            }
            catch (WebSocketException) { refused = true; }
            catch (OperationCanceledException) { refused = true; }
            Check(refused, "a non-extension origin is refused");
            Check(bridge.Connected, "the legitimate extension stays connected");
        }
        catch (Exception ex)
        {
            Check(false, "bridge smoke completed: " + ex.GetType().Name + ": " + ex.Message);
        }
        finally
        {
            bridge.Stop();
            Check(!bridge.Connected, "the bridge closes cleanly");
        }
    }

    static async Task<string> Receive(ClientWebSocket socket, CancellationToken token)
    {
        var buffer = new byte[16 * 1024];
        using var memory = new MemoryStream();
        while (true)
        {
            var result = await socket.ReceiveAsync(buffer.AsMemory(), token);
            if (result.MessageType == WebSocketMessageType.Close) return "";
            memory.Write(buffer, 0, result.Count);
            if (result.EndOfMessage) return Encoding.UTF8.GetString(memory.ToArray());
        }
    }

    static Task Send(ClientWebSocket socket, string text) =>
        socket.SendAsync(Encoding.UTF8.GetBytes(text), WebSocketMessageType.Text, true, CancellationToken.None);

    static void Check(bool ok, string what)
    {
        if (!ok) _failed++;
        Program.SmokeLog((ok ? "stage18-smoke: [ok] " : "stage18-smoke: [FAIL] ") + what);
        Console.WriteLine((ok ? "[ok] " : "[FAIL] ") + what);
    }
}
