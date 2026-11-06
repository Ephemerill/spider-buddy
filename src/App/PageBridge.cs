using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using SpiderBuddy.Core;

namespace SpiderBuddy.App;

/// <summary>
/// The browser extension's loopback line (spec 18.3). A tiny RFC 6455 server on 127.0.0.1 only:
/// it accepts browser-extension origins, sends which windows are being climbed, and reads only
/// scrolling geometry and change notices. No page content ever arrives or is stored.
/// </summary>
public sealed class PageBridge
{
    public static readonly int[] Ports = { 47219, 47220, 47221 };

    readonly object _gate = new();
    readonly List<TcpClient> _clients = new();
    readonly Dictionary<int, PageBridgePage> _pages = new();
    readonly List<Rect> _wanted = new();
    TcpListener? _listener;
    CancellationTokenSource? _cancellation;
    int _portIndex;
    bool _started;

    public event Action<int>? OnScroll;
    public event Action<int>? OnChange;

    public bool Connected { get; private set; }
    public bool Running => _listener is not null;
    public int Port { get; private set; }
    public string Status => Connected ? $"Extension connected on 127.0.0.1:{Port}" : Running ? "Waiting for the browser extension" : "Extension bridge unavailable";

    public IReadOnlyList<PageBridgePage> Pages
    {
        get { lock (_gate) return _pages.Values.ToList(); }
    }

    public void Start()
    {
        if (_started) return;
        _started = true;
        _portIndex = 0;
        TryStart();
    }

    void TryStart()
    {
        StopListenerOnly();
        for (; _portIndex < Ports.Length; _portIndex++)
        {
            try
            {
                var l = new TcpListener(IPAddress.Loopback, Ports[_portIndex]);
                l.Start();
                _listener = l;
                Port = Ports[_portIndex];
                _cancellation = new CancellationTokenSource();
                _ = AcceptLoop(l, _cancellation.Token);
                return;
            }
            catch (SocketException) { }
        }
    }

    void StopListenerOnly()
    {
        try { _cancellation?.Cancel(); } catch { }
        try { _listener?.Stop(); } catch { }
        _listener = null;
        _cancellation = null;
    }

    public void Stop()
    {
        _started = false;
        StopListenerOnly();
        lock (_gate)
        {
            foreach (var c in _clients.ToList())
            {
                try { c.Close(); } catch { }
            }
            _clients.Clear();
            _pages.Clear();
            _wanted.Clear();
            Connected = false;
        }
    }

    async Task AcceptLoop(TcpListener listener, CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            TcpClient client;
            try { client = await listener.AcceptTcpClientAsync(token); }
            catch (OperationCanceledException) { return; }
            catch (ObjectDisposedException) { return; }
            catch (SocketException) { return; }
            _ = Task.Run(() => Handle(client, token), token);
        }
    }

    async Task Handle(TcpClient client, CancellationToken token)
    {
        NetworkStream? stream = null;
        try
        {
            client.NoDelay = true;
            client.ReceiveTimeout = 0;
            stream = client.GetStream();
            var header = await ReadHeaders(stream, token);
            if (header is null) return;
            string? key = null, origin = "";
            foreach (var line in header.Split("\r\n"))
            {
                int colon = line.IndexOf(':');
                if (colon <= 0) continue;
                string name = line[..colon].Trim().ToLowerInvariant();
                string value = line[(colon + 1)..].Trim();
                if (name == "sec-websocket-key") key = value;
                else if (name == "origin") origin = value;
            }
            bool allowed = origin.StartsWith("chrome-extension://", StringComparison.OrdinalIgnoreCase)
                || origin.StartsWith("moz-extension://", StringComparison.OrdinalIgnoreCase)
                || origin.StartsWith("safari-web-extension://", StringComparison.OrdinalIgnoreCase);
            if (key is null || !allowed)
            {
                await WriteAll(stream, Encoding.ASCII.GetBytes("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n"), token);
                return;
            }
            string accept = Convert.ToBase64String(SHA1.HashData(Encoding.ASCII.GetBytes(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")));
            string response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
                $"Sec-WebSocket-Accept: {accept}\r\n\r\n";
            await WriteAll(stream, Encoding.ASCII.GetBytes(response), token);

            lock (_gate)
            {
                _clients.Add(client);
                Connected = true;
            }
            SendWant(client);
            while (!token.IsCancellationRequested)
            {
                var frame = await ReadFrame(stream, token);
                if (frame is null) break;
                switch (frame.Value.opcode)
                {
                    case 0x8: // close
                        await SendFrame(client, 0x8, Array.Empty<byte>());
                        return;
                    case 0x9: // ping
                        await SendFrame(client, 0xA, frame.Value.payload);
                        continue;
                    case 0xA: continue;
                    case 0x1:
                        if (frame.Value.payload.Length > 2_000_000) return;
                        HandleText(Encoding.UTF8.GetString(frame.Value.payload));
                        break;
                }
            }
        }
        catch { }
        finally
        {
            lock (_gate)
            {
                _clients.Remove(client);
                if (_clients.Count == 0)
                {
                    Connected = false;
                    _pages.Clear();
                }
            }
            try { stream?.Dispose(); } catch { }
            try { client.Close(); } catch { }
        }
    }

    static async Task<string?> ReadHeaders(NetworkStream stream, CancellationToken token)
    {
        var bytes = new List<byte>(512);
        var one = new byte[1];
        while (bytes.Count < 16_384)
        {
            int n = await stream.ReadAsync(one.AsMemory(0, 1), token);
            if (n <= 0) return null;
            bytes.Add(one[0]);
            int c = bytes.Count;
            if (c >= 4 && bytes[c - 4] == '\r' && bytes[c - 3] == '\n' && bytes[c - 2] == '\r' && bytes[c - 1] == '\n')
                return Encoding.ASCII.GetString(bytes.ToArray());
        }
        return null;
    }

    static async Task WriteAll(NetworkStream stream, byte[] data, CancellationToken token)
    {
        await stream.WriteAsync(data.AsMemory(), token);
        await stream.FlushAsync(token);
    }

    static async Task<(byte opcode, byte[] payload)?> ReadFrame(NetworkStream stream, CancellationToken token)
    {
        var head = new byte[2];
        if (!await ReadExact(stream, head, token)) return null;
        byte opcode = (byte)(head[0] & 0x0F);
        bool masked = (head[1] & 0x80) != 0;
        long len = head[1] & 0x7F;
        if (len == 126)
        {
            var ext = new byte[2];
            if (!await ReadExact(stream, ext, token)) return null;
            len = (ext[0] << 8) | ext[1];
        }
        else if (len == 127)
        {
            var ext = new byte[8];
            if (!await ReadExact(stream, ext, token)) return null;
            len = 0;
            for (int i = 0; i < 8; i++) len = (len << 8) | ext[i];
        }
        if (len < 0 || len > 4_000_000) return null;
        var mask = new byte[4];
        if (masked && !await ReadExact(stream, mask, token)) return null;
        var payload = new byte[(int)len];
        if (len > 0 && !await ReadExact(stream, payload, token)) return null;
        if (masked) for (int i = 0; i < payload.Length; i++) payload[i] ^= mask[i % 4];
        return (opcode, payload);
    }

    static async Task<bool> ReadExact(NetworkStream stream, byte[] data, CancellationToken token)
    {
        int read = 0;
        while (read < data.Length)
        {
            int n = await stream.ReadAsync(data.AsMemory(read), token);
            if (n <= 0) return false;
            read += n;
        }
        return true;
    }

    static async Task SendFrame(TcpClient client, byte opcode, byte[] payload)
    {
        try
        {
            var stream = client.GetStream();
            var head = new List<byte> { (byte)(0x80 | opcode) };
            if (payload.Length < 126) head.Add((byte)payload.Length);
            else if (payload.Length <= ushort.MaxValue) { head.Add(126); head.Add((byte)(payload.Length >> 8)); head.Add((byte)payload.Length); }
            else
            {
                head.Add(127);
                long n = payload.Length;
                for (int i = 7; i >= 0; i--) head.Add((byte)(n >> (i * 8)));
            }
            await stream.WriteAsync(head.ToArray());
            if (payload.Length > 0) await stream.WriteAsync(payload);
            await stream.FlushAsync();
        }
        catch { }
    }

    public void Want(IReadOnlyList<Rect> worldFrames)
    {
        var vs = System.Windows.Forms.SystemInformation.VirtualScreen;
        var rects = worldFrames.Select(f => new Rect(
            vs.Left + f.X, vs.Bottom - f.MaxY, f.W, f.H)).ToList();
        lock (_gate)
        {
            if (rects.Count == _wanted.Count && rects.Zip(_wanted).All(p => p.First.ApproximatelyEquals(p.Second, 1)))
                return;
            _wanted.Clear();
            _wanted.AddRange(rects);
            var data = WantJson();
            foreach (var c in _clients.ToList()) SendText(c, data);
        }
    }

    void SendWant(TcpClient client)
    {
        lock (_gate) SendText(client, WantJson());
    }

    byte[] WantJson()
    {
        var windows = new JsonArray();
        lock (_gate)
        {
            foreach (var r in _wanted)
                windows.Add(new JsonObject
                {
                    ["left"] = r.MinX, ["top"] = r.MinY, ["width"] = r.W, ["height"] = r.H
                });
        }
        return Encoding.UTF8.GetBytes(new JsonObject { ["type"] = "want", ["windows"] = windows }.ToJsonString());
    }

    void SendText(TcpClient client, byte[] data) => _ = SendFrame(client, 0x1, data);

    public PageBridgePage? PageIn(Rect worldFrame)
    {
        var vs = System.Windows.Forms.SystemInformation.VirtualScreen;
        var r = new Rect(vs.Left + worldFrame.X, vs.Bottom - worldFrame.MaxY, worldFrame.W, worldFrame.H);
        lock (_gate)
        {
            foreach (var p in _pages.Values)
            {
                if (Math.Abs(p.Window.MinX - r.MinX) <= 6 && Math.Abs(p.Window.MinY - r.MinY) <= 6
                    && Math.Abs(p.Window.W - r.W) <= 6 && Math.Abs(p.Window.H - r.H) <= 6) return p;
            }
        }
        return null;
    }

    void HandleText(string json)
    {
        JsonObject? m;
        try { m = JsonNode.Parse(json) as JsonObject; }
        catch { return; }
        if (m is null) return;
        string type = Str(m["type"]);
        int tab = (int)Num(m["tab"], -1);
        switch (type)
        {
            case "layout":
                if (tab < 0) return;
                var w = m["window"] as JsonObject;
                var v = m["view"] as JsonObject;
                if (w is null || v is null) return;
                var p = new PageBridgePage
                {
                    Tab = tab,
                    Window = new Rect(Num(w["left"]), Num(w["top"]), Num(w["width"]), Num(w["height"])),
                    Viewport = new SizeD(Num(v["w"]), Num(v["h"])),
                    Dpr = Math.Max(0.5, Num(v["dpr"], 1)),
                    LaidOutAt = Environment.TickCount64 / 1000.0
                };
                if (m["scrollers"] is JsonArray scrollers)
                {
                    foreach (var item in scrollers.OfType<JsonArray>())
                    {
                        if (item.Count < 8) continue;
                        int id = (int)Num(item[0]), carrier = (int)Num(item[1], -1);
                        var s = new PageScroller
                        {
                            Id = id, Carrier = carrier,
                            Rect = new Rect(Num(item[2]), Num(item[3]), Num(item[4]), Num(item[5])),
                            Offset = new V2(Num(item[6]), Num(item[7]))
                        };
                        p.Scrollers[id] = s;
                        p.Offsets[id] = s.Offset;
                    }
                }
                if (m["fixed"] is JsonArray fixedRects)
                {
                    foreach (var item in fixedRects.OfType<JsonArray>())
                    {
                        if (item.Count < 4) continue;
                        p.Fixed.Add(new Rect(Num(item[0]), Num(item[1]), Num(item[2]), Num(item[3])));
                    }
                }
                lock (_gate) _pages[tab] = p;
                OnChange?.Invoke(tab);
                break;
            case "scroll":
                lock (_gate)
                {
                    if (!_pages.TryGetValue(tab, out var q)) return;
                    if (m["s"] is JsonArray scrolls)
                    {
                        foreach (var item in scrolls.OfType<JsonArray>())
                        {
                            if (item.Count < 3) continue;
                            q.Offsets[(int)Num(item[0])] = new V2(Num(item[1]), Num(item[2]));
                        }
                    }
                }
                OnScroll?.Invoke(tab);
                break;
            case "changed":
                OnChange?.Invoke(tab);
                break;
            case "gone":
                lock (_gate) _pages.Remove(tab);
                break;
        }
    }

    static string Str(JsonNode? n)
    {
        try { return n?.GetValue<string>() ?? ""; }
        catch { return ""; }
    }

    static double Num(JsonNode? n, double fallback = 0)
    {
        if (n is null) return fallback;
        try { return n.GetValue<double>(); } catch { }
        try { return n.GetValue<int>(); } catch { }
        return fallback;
    }
}
