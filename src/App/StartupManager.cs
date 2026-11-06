using Microsoft.Win32;

namespace SpiderBuddy.App;

public static class StartupManager
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string ValueName = "SpiderBuddy";

    public static bool IsEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: false);
            return key?.GetValue(ValueName) is string value && value.Length > 0;
        }
        catch { return false; }
    }

    public static void Set(bool on)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true)
                ?? Registry.CurrentUser.CreateSubKey(RunKey, writable: true);
            if (key is null) return;
            if (on)
            {
                string? exe = Environment.ProcessPath;
                if (!string.IsNullOrWhiteSpace(exe)) key.SetValue(ValueName, "\"" + exe + "\"");
            }
            else key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
        catch { }
    }
}
