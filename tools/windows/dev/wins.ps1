# Lists SpiderBuddy's top-level windows: handle, class, visible, rect, extended style, layered alpha.
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public class W {
  public delegate bool P(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(P p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern long GetWindowLongPtr(IntPtr h, int i);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
$ids = @(Get-Process SpiderBuddy -ErrorAction SilentlyContinue | % Id)
if (-not $ids) { "not running"; return }
$found = New-Object Collections.Generic.List[string]
[W]::EnumWindows({ param($h, $l)
  $pid2 = 0; [void][W]::GetWindowThreadProcessId($h, [ref]$pid2)
  if ($ids -contains $pid2) {
    $c = New-Object Text.StringBuilder 256; [void][W]::GetClassName($h, $c, 256)
    $t = New-Object Text.StringBuilder 256; [void][W]::GetWindowText($h, $t, 256)
    $r = New-Object W+RECT; [void][W]::GetWindowRect($h, [ref]$r)
    $ex = [W]::GetWindowLongPtr($h, -20)
    $found.Add(("{0} {1} '{2}' vis={3} [{4},{5} {6}x{7}] ex=0x{8:x}" -f $h, $c, $t, [W]::IsWindowVisible($h), $r.L, $r.T, ($r.R-$r.L), ($r.B-$r.T), $ex))
  }
  $true }, [IntPtr]::Zero) | Out-Null
"pids: $ids"
$found
