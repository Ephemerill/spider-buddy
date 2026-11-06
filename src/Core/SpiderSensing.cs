namespace SpiderBuddy.Core;

public enum Commotion { Louder, Quieter, Brighter, Dimmer }

/// <summary>Stage 14 — the portable side of sensing the machine (spec 14).</summary>
public sealed partial class Spider
{
    // ---- cinema manners (14.1)
    public bool Cinema { get; private set; }
    public Rect CinemaScreen { get; private set; }
    public V2 CinemaSeat { get; private set; }
    public double CinemaSince { get; private set; } = -99;
    public double CinemaPace = 0.6;

    // ---- power (14.2)
    public bool LowPower { get; private set; }
    public bool LowPowerOverride;
    public bool OnCharger { get; private set; }
    public double ChargePerkUntil = -1;
    public int ClockHz => LowPower ? 30 : 60;

    // ---- weather (14.3)
    public bool FeelWeather = true;
    public bool ShowRain;
    public int WeatherCode { get; private set; }
    public double WeatherWind, WeatherTemperature;
    public bool WeatherIsDay = true;
    public double WeatherAt = -9999;
    public double RainThoughtUntil = -1;

    // ---- notifications (14.4)
    public bool FeelCommotion = true;
    public int BannerCount { get; private set; }
    public int CommotionCount { get; private set; }

    // ---- music (14.5)
    public bool DanceToMusic = true;
    public bool MusicPlaying { get; private set; }
    public double MusicBpm, MusicConfidence, MusicEnergy;
    public double MusicSteady, MusicSilentFor;
    public bool MusicWelcomed { get; private set; }
    public double GrooveRestUntil = -1;
    public int DanceCount { get; private set; }

    // ---- away (14.6)
    public bool Dormant { get; private set; }
    public bool GreetOnWaking = true;

    public void EnterCinema(Rect screen)
    {
        if (Cinema) return;
        Cinema = true;
        CinemaScreen = screen;
        CinemaSince = Time;
        var inner = screen.Inset(-24);
        var corners = new[] { inner.BottomLeft, inner.BottomRight, inner.TopLeft, inner.TopRight };
        CinemaSeat = corners.OrderBy(c => c.DistanceTo(Pos)).First();
        Play(Activity.Walk, 3);
    }

    public void ExitCinema()
    {
        Cinema = false;
        WalkSpeedScale = 1;
    }

    void UpdateCinema(double dt)
    {
        WalkSpeedScale = CinemaPace;
        if (Pos.DistanceTo(CinemaSeat) > 22 * Scale)
        {
            MoveTowardPoint(CinemaSeat, 58 * Scale, dt);
            if (Activity != Activity.Walk) Play(Activity.Walk, 2);
        }
        else if (Activity != Activity.Watch) Play(Activity.Watch, 2);
    }

    public void SetLowPower(bool on)
    {
        LowPower = on;
        if (on) Drowsy = Math.Max(Drowsy, 0.6);
        else Drowsy = 0;
    }

    public void PlugIn()
    {
        if (OnCharger) return;
        OnCharger = true;
        ChargePerkUntil = Time + 2.5;
        Happy.Velocity = 8;
        ShowEmote(PointerEmote.Sparkle, 1.2);
        if (Mode == Mode.Attached && Activity is not (Activity.Sleep or Activity.Groove))
            Play(Activity.Hop, 0.5);
    }

    public void Unplug() => OnCharger = false;

    public void SetWeather(int code, double wind, bool isDay, double temperature)
    {
        WeatherCode = code;
        WeatherWind = wind;
        WeatherIsDay = isDay;
        WeatherTemperature = temperature;
        WeatherAt = Time;
        Raining = (code >= 51 && code <= 67) || (code >= 80 && code <= 82) || (code >= 95 && code <= 99);
        if (Raining) RainThoughtUntil = Time + 3.5;
    }

    public void OnBanner()
    {
        BannerCount++;
        if (!FeelCommotion) return;
        Startled.Velocity = 7;
        if (Mode == Mode.Attached) Play(Activity.Hop, 0.5);
    }

    public void OnCommotion(Commotion kind)
    {
        CommotionCount++;
        if (!FeelCommotion) return;
        if (Mode == Mode.Attached && Activity is not (Activity.Sleep or Activity.Groove))
            Play(Activity.Look, 1.2);
    }

    public void SetMusic(bool playing, double bpm = 0, double confidence = 0, double energy = 0)
    {
        MusicPlaying = playing;
        MusicBpm = bpm;
        MusicConfidence = confidence;
        MusicEnergy = energy;
    }

    void UpdateMusic(double dt)
    {
        if (MusicPlaying)
        {
            MusicSilentFor = 0;
            if (MusicConfidence >= 0.45) MusicSteady += dt;
        }
        else
        {
            MusicSteady = 0;
            MusicSilentFor += dt;
            if (MusicSilentFor > 30) MusicWelcomed = false;
        }

        if (!MusicPlaying || !DanceToMusic || MusicSteady < 3 || MusicWelcomed || Dormant) return;
        double habit = Design.Habits.DanceMusic;
        if (habit <= 0.01) return;
        double weight = Habits.Weight(habit);
        double cooldown = Math.Max(3, (40 + 50 * ActivePersonality.Laziness) / Math.Sqrt(Math.Max(1, weight)));
        if (Time < GrooveRestUntil) return;
        MusicWelcomed = true;
        DanceCount++;
        GrooveRestUntil = Time + cooldown;
        if (Mode == Mode.Attached) Play(Activity.Groove, 6);
        Happy.Velocity = 5;
    }

    public void SetLocked(bool locked)
    {
        if (locked)
        {
            Dormant = true;
            if (Mode == Mode.Attached) Play(Activity.Sleep, 9999);
        }
        else
        {
            Dormant = false;
            if (GreetOnWaking && Mode == Mode.Attached)
            {
                Play(Activity.Greet, 1.6);
                Happy.Velocity = 5;
            }
        }
    }

    void UpdateSensing(double dt)
    {
        if (Dormant) return;
        UpdateMusic(dt);
        if (Cinema && WalkSpeedScale == 1) WalkSpeedScale = CinemaPace;
    }
}
