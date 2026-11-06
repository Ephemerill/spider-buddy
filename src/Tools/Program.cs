namespace SpiderBuddy.Tools;

/// <summary>
/// Headless harness entry point. Mirrors the macOS tools: each subcommand is a scripted
/// check that prints [ok]/[FAIL] and exits non-zero on any failure.
/// </summary>
public static class Program
{
    public static int Main(string[] args)
    {
        string cmd = args.Length > 0 ? args[0].ToLowerInvariant() : "help";
        return cmd switch
        {
            "stage1" => Stage1.Run(args),
            "stage2" => Stage2.Run(args),
            "stage3" => Stage3.Run(args),
            "stage4" => Stage4.Run(args),
            "stage5" => Stage5.Run(args),
            "stage6" => Stage6.Run(args),
            "stage7" => Stage7.Run(args),
            "stage8" => Stage8.Run(args),
            "stage9" => Stage9.Run(args),
            "stage10" => Stage10.Run(args),
            "stage11" => Stage11.Run(args),
            "stage12" => Stage12.Run(args),
            "stage13" => Stage13.Run(args),
            "stage14" => Stage14.Run(args),
            "stage15" => Stage15.Run(args),
            "stage17" => Stage17.Run(args),
            "stage18" => Stage18.Run(args),
            "stage19" => Stage19.Run(args),
            "stage20" => Stage20.Run(args.Skip(1).ToArray()),
            "update-key" or "sign-appcast" or "verify-appcast" => ReleaseTool.Run(args),
            "gaitdiag" => GaitDiag.Run(args),
            "all" => RunAll(args),
            "help" or "--help" or "-h" => Help(),
            _ => Unknown(cmd),
        };
    }

    static int RunAll(string[] args)
    {
        int worst = 0;
        void Step(Func<int> f) { int r = f(); if (r > worst) worst = r; }
        Step(() => Stage1.Run(args));
        Step(() => Stage2.Run(args));
        Step(() => Stage3.Run(args));
        Step(() => Stage4.Run(args));
        Step(() => Stage5.Run(args));
        Step(() => Stage6.Run(args));
        Step(() => Stage7.Run(args));
        Step(() => Stage8.Run(args));
        Step(() => Stage9.Run(args));
        Step(() => Stage10.Run(args));
        Step(() => Stage11.Run(args));
        Step(() => Stage12.Run(args));
        Step(() => Stage13.Run(args));
        Step(() => Stage14.Run(args));
        Step(() => Stage15.Run(args));
        Step(() => Stage17.Run(args));
        Step(() => Stage18.Run(args));
        Step(() => Stage19.Run(args));
        Step(() => Stage20.Run(Array.Empty<string>()));
        Console.WriteLine();
        Console.WriteLine(worst == 0 ? "=== ALL SUITES OK ===" : "=== SUITE FAILURES ===");
        return worst;
    }

    static int Help()
    {
        Console.WriteLine("""
        Spider Buddy — headless tools

          stage1    foundations: math, springs, silk rope, settings, frame clock
          stage5    pointer foundations (partial stage acceptance)
          stage6    the brain: decisions, moods, repertoire
          stage7    air: leaps, falling, throws, landing
          stage8    silk: lines, rappel, climb, swing, mantle, hammock
          stage18   talking spider, page reader, web ledges, extension files
          stage19   packaging, signed updates, appcast and bug-report plumbing
          stage20   verification harness: sim, film, jerk, legs, bench, perch, pages, gate
          update-key / sign-appcast / verify-appcast   Windows release helpers
          all       every suite in order

        Every suite prints [ok]/[FAIL] lines and exits non-zero if anything failed.
        """);
        return 0;
    }

    static int Unknown(string cmd)
    {
        Console.Error.WriteLine($"unknown command '{cmd}' — try: stage1, all");
        return 2;
    }
}
