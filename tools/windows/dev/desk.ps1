# Desktop-session helpers, run through the bridge with PowerShell's full path (a bare name is taken as relative to the
# repo and never starts):
#   lap run --log desk C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass \
#       -File C:\Users\User\Documents\Projects\spider-buddy\tools\windows\dev\desk.ps1 <cmd> ...
# Physical pixels throughout (the script is per-monitor DPI aware).
#   shot <file>                    the whole virtual screen to a PNG
#   click <x> <y> [left|right]     move there and click
#   key <vk>                       press and release a virtual key (27 = Escape)
#   menu <file>                    right-click the spider (its sprite window), screenshot the menu, then Escape
#   overflow <file>                open the notification area's overflow (the ^ by the clock), screenshot, then Escape
#   menutest <dir> <exe> <x> <y>   SPIDER_MINIMIZE_TEST parks the spider on its window's top 2 s in: right-click it at
#                                  x,y, screenshot, dismiss with a click elsewhere (or Escape with DESK_DISMISS=escape),
#                                  screenshot; the app's output (SPIDER_MENU_LOG) in <dir>
#   trayclick <file> <x> <y>       open the overflow, click the icon at x,y in it, screenshot what opens
#   roam <dir> <exe>               the spider wherever it is: found against a screenshot taken before the app starts,
#                                  right-clicked, then Escape (DESK_DISMISS=escape) or a click away; output in <dir>
#   minitest <dir> <exe>           SPIDER_MINIMIZE_TEST (welcomed): screenshots while the test window is open and while
#                                  minimized, and the app's output, in <dir>
param([string]$cmd, [string]$a1, [string]$a2, [string]$a3, [string]$a4)
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.Runtime.InteropServices;
public class D {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, IntPtr e);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  public delegate bool P(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(P p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
  public static string Fore() { IntPtr h = GetForegroundWindow(); uint p; GetWindowThreadProcessId(h, out p); var sb = new System.Text.StringBuilder(256); GetClassName(h, sb, 256); return sb + " pid " + p; }
  [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  // The centre of what differs between two screenshots inside r (the spider, against the desktop it stands on).
  public static int[] DiffCentre(System.Drawing.Bitmap a, System.Drawing.Bitmap b, RECT r) {
    long sx = 0, sy = 0, n = 0;
    for (int y = Math.Max(r.T, 0); y < Math.Min(r.B, a.Height); y += 2)
      for (int x = Math.Max(r.L, 0); x < Math.Min(r.R, a.Width); x += 2) {
        var p = a.GetPixel(x, y); var q = b.GetPixel(x, y);
        if (Math.Abs(p.R - q.R) + Math.Abs(p.G - q.G) + Math.Abs(p.B - q.B) > 60) { sx += x; sy += y; n++; }
      }
    return n == 0 ? new int[] { -1, -1, 0 } : new int[] { (int)(sx / n), (int)(sy / n), (int)n };
  }
  // The spider's sprite: SpiderBuddy's smallest visible window.
  public static RECT Sprite(uint pid) {
    RECT best = new RECT(); int area = int.MaxValue;
    EnumWindows((h, l) => { uint p2; GetWindowThreadProcessId(h, out p2); RECT r;
      if (p2 == pid && IsWindowVisible(h) && GetWindowRect(h, out r)) { int a = (r.R - r.L) * (r.B - r.T); if (a > 0 && a < area) { area = a; best = r; } }
      return true; }, IntPtr.Zero);
    return best;
  }
}
"@
[void][D]::SetProcessDpiAwarenessContext([IntPtr](-4))
function Shot([string]$file) {
    $x = [D]::GetSystemMetrics(76); $y = [D]::GetSystemMetrics(77); $w = [D]::GetSystemMetrics(78); $h = [D]::GetSystemMetrics(79)
    $b = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen($x, $y, 0, 0, $b.Size)
    $b.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $b.Dispose()
}
switch ($cmd) {
    'shot' { Shot $a1 }
    'click' {
        [void][D]::SetCursorPos([int]$a1, [int]$a2)
        Start-Sleep -Milliseconds 80
        if ($a3 -eq 'right') { [D]::mouse_event(0x0008, 0, 0, 0, [IntPtr]::Zero); [D]::mouse_event(0x0010, 0, 0, 0, [IntPtr]::Zero) }
        else { [D]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero); [D]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero) }
    }
    'menu' {
        $sp = Get-Process SpiderBuddy -ErrorAction Stop | Select-Object -First 1
        $r = [D]::Sprite([uint32]$sp.Id)
        $x = [int](($r.L + $r.R) / 2); $y = [int](($r.T + $r.B) / 2)
        "sprite $($r.L),$($r.T) $($r.R - $r.L)x$($r.B - $r.T); right-click at $x,$y"
        [void][D]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 80
        [D]::mouse_event(0x0008, 0, 0, 0, [IntPtr]::Zero); [D]::mouse_event(0x0010, 0, 0, 0, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 900; Shot $a1
        "foreground with the menu open: $([D]::Fore()) (app pid $($sp.Id))"
        [D]::keybd_event(27, 0, 0, [IntPtr]::Zero); [D]::keybd_event(27, 0, 2, [IntPtr]::Zero)
    }
    'overflow' {
        # The ^ button: the taskbar's notification area chevron.
        $tray = [D]::FindWindow('Shell_TrayWnd', $null)
        $notify = [D]::FindWindowEx($tray, [IntPtr]::Zero, 'TrayNotifyWnd', $null)
        $r = New-Object D+RECT; [void][D]::GetWindowRect($notify, [ref]$r)
        "notify area $($r.L),$($r.T) $($r.R - $r.L)x$($r.B - $r.T)"
        $x = if ($a2) { [int]$a2 } else { $r.L + 24 }; $y = [int](($r.T + $r.B) / 2)
        [void][D]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 80
        [D]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero); [D]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 900; Shot $a1
        [D]::keybd_event(27, 0, 0, [IntPtr]::Zero); [D]::keybd_event(27, 0, 2, [IntPtr]::Zero)
    }
    'trayclick' {
        $tray = [D]::FindWindow('Shell_TrayWnd', $null)
        $notify = [D]::FindWindowEx($tray, [IntPtr]::Zero, 'TrayNotifyWnd', $null)
        $r = New-Object D+RECT; [void][D]::GetWindowRect($notify, [ref]$r)
        [void][D]::SetCursorPos($r.L + 24, [int](($r.T + $r.B) / 2)); Start-Sleep -Milliseconds 60
        [D]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero); [D]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 1500
        [void][D]::SetCursorPos([int]$a2, [int]$a3); Start-Sleep -Milliseconds 300
        [D]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero); [D]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 1200; Shot $a1
    }
    'key' { [D]::keybd_event([byte][int]$a1, 0, 0, [IntPtr]::Zero); [D]::keybd_event([byte][int]$a1, 0, 2, [IntPtr]::Zero) }
    'menutest' {
        New-Item -ItemType Directory -Force $a1 | Out-Null
        $env:SPIDER_MINIMIZE_TEST = '1'; $env:SPIDER_MENU_LOG = '1'
        $p = Start-Process $a2 -ArgumentList '-welcomed', 'YES' -PassThru -RedirectStandardOutput "$a1\menutest.log"
        Start-Sleep -Milliseconds 2800
        [void][D]::SetCursorPos([int]$a3, [int]$a4); Start-Sleep -Milliseconds 60
        [D]::mouse_event(0x0008, 0, 0, 0, [IntPtr]::Zero); [D]::mouse_event(0x0010, 0, 0, 0, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 350; Shot "$a1\menu-open.png"; "foreground: $([D]::Fore())"
        # Dismissed by Escape (with a fourth argument "escape") or by a click on the desktop well away from it.
        if ($env:DESK_DISMISS -eq 'escape') {
            [D]::keybd_event(27, 0, 0, [IntPtr]::Zero); [D]::keybd_event(27, 0, 2, [IntPtr]::Zero)
            Start-Sleep -Milliseconds 250; Shot "$a1\menu-dismissed.png"
            [void]$p.WaitForExit(15000); return
        }
        [void][D]::SetCursorPos(200, 900); Start-Sleep -Milliseconds 60
        [D]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero); [D]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 250; Shot "$a1\menu-dismissed.png"
        [void]$p.WaitForExit(15000)
    }
    'roam' {
        New-Item -ItemType Directory -Force $a1 | Out-Null
        Shot "$a1\before.png"
        $env:SPIDER_MENU_LOG = '1'
        $p = Start-Process $a2 -ArgumentList '-welcomed', 'YES' -PassThru -RedirectStandardOutput "$a1\roam.log"
        Start-Sleep -Seconds 10
        $r = [D]::Sprite([uint32]$p.Id)
        Shot "$a1\with.png"
        $a = [System.Drawing.Bitmap]::FromFile("$a1\before.png"); $b = [System.Drawing.Bitmap]::FromFile("$a1\with.png")
        $c = [D]::DiffCentre($a, $b, $r); $a.Dispose(); $b.Dispose()
        "sprite $($r.L),$($r.T) $($r.R - $r.L)x$($r.B - $r.T); spider at $($c[0]),$($c[1]) ($($c[2]) samples)"
        if ($c[2] -gt 0) {
            [void][D]::SetCursorPos($c[0], $c[1]); Start-Sleep -Milliseconds 40
            [D]::mouse_event(0x0008, 0, 0, 0, [IntPtr]::Zero); [D]::mouse_event(0x0010, 0, 0, 0, [IntPtr]::Zero)
            Start-Sleep -Milliseconds 500; Shot "$a1\roam-open.png"; "foreground: $([D]::Fore())"
            if ($env:DESK_DISMISS -eq 'escape') { [D]::keybd_event(27, 0, 0, [IntPtr]::Zero); [D]::keybd_event(27, 0, 2, [IntPtr]::Zero) }
            else { [void][D]::SetCursorPos(200, 900); Start-Sleep -Milliseconds 40; [D]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero); [D]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero) }
            Start-Sleep -Milliseconds 400; Shot "$a1\roam-after.png"
        }
        Stop-Process -Id $p.Id -Force
    }
    'minitest' {
        New-Item -ItemType Directory -Force $a1 | Out-Null
        $env:SPIDER_MINIMIZE_TEST = '1'
        $p = Start-Process $a2 -ArgumentList '-welcomed', 'YES' -PassThru -RedirectStandardOutput "$a1\minimize.log"
        Start-Sleep -Milliseconds 2600; Shot "$a1\open.png"
        Start-Sleep -Milliseconds 1500; Shot "$a1\minimized.png"
        [void]$p.WaitForExit(15000)
    }
}
