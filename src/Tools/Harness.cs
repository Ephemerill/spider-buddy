namespace SpiderBuddy.Tools;

/// <summary>
/// A tiny [ok]/[FAIL] check runner, matching the macOS tools' output style (spec Stage 20)
/// so results can be read the same way on both platforms.
/// </summary>
public static class Harness
{
    public static int Passed;
    public static int Failed;
    public static readonly List<string> Failures = new();

    public static void Section(string name) =>
        Console.WriteLine($"\n=== {name} ===");

    public static void Ok(string what)
    {
        Passed++;
        Console.WriteLine($"  [ok] {what}");
    }

    public static void Fail(string what, string? detail = null)
    {
        Failed++;
        string line = detail is null ? what : $"{what} — {detail}";
        Failures.Add(line);
        Console.WriteLine($"  [FAIL] {line}");
    }

    public static void Check(bool condition, string what, string? detail = null)
    {
        if (condition) Ok(what); else Fail(what, detail);
    }

    public static void Near(double actual, double expected, double tol, string what)
    {
        bool good = Math.Abs(actual - expected) <= tol;
        Check(good, what, good ? null : $"expected {expected:0.####} ±{tol:0.####}, got {actual:0.####}");
    }

    /// <summary>Assert, then give a short summary and return the process exit code.</summary>
    public static int Summarise(string label)
    {
        Console.WriteLine();
        if (Failed == 0)
        {
            Console.WriteLine($"ALL OK — {Passed} checks passed ({label})");
            return 0;
        }
        Console.WriteLine($"FAILURES — {Failed} failed, {Passed} passed ({label})");
        foreach (var f in Failures) Console.WriteLine($"  ✗ {f}");
        return 1;
    }
}
