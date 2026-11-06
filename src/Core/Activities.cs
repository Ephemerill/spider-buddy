namespace SpiderBuddy.Core;

public enum Activity
{
    Idle = 0, Walk, Sneak, Scurry, Look, Rest, Groom, Sleep, Wave, Startle, Crouch, Turn,
    Peek, Stretch, Shake, Wiggle, Bounce, Curious, ArmsUp, Roll, Dance, Glance, Peer, Pushup,
    LegStretch, Shoot, Eat, Stare, Hop, Drum, Greet, Peekaboo, Fasten, Groove, Watch, Brace,
    Bask, Feel, Drink, DoubleTake, Sigh, Fidget, Scratch, Muse, Spin, Explore, Flee, Approach,
    Swing, Rappel, Climb, Cling, Hunt, Pounce, Carry, Nap, Build, Mend, Finish, GaitTurn
}

/// <summary>
/// The character of every activity (spec 4.3). `u = activityTime / activityDur`.
/// `legsFree` means the legs are placed by the pose, not by the walk gait.
/// </summary>
public struct Posture
{
    public double Speed;      // multiplier on walkSpeed
    public double Lift;       // units above the ledge
    public double Pitch;      // radians, nose up positive
    public double Crouch;     // 0…1
    public double Wag;        // abdomen wiggle amplitude
    public double Lid;        // heavy eyelids
    public bool LegsFree;

    public static Posture Idle => new() { Speed = 0 };

    /// <summary>The posture for an activity at time u through it (spec 4.3).</summary>
    public static Posture For(Activity a, double u, GaitConfig gait, Rng rng)
    {
        u = M.Clamp01(u);
        double sin1 = Math.Sin(u * M.Pi);
        var p = new Posture();

        switch (a)
        {
            case Activity.Idle:
                break;

            case Activity.Walk:
            case Activity.Sneak:
            case Activity.Scurry:
            {
                p.Speed = a switch { Activity.Sneak => 0.42, Activity.Scurry => 1.9, _ => 1.0 };
                p.Lift = 0; p.Pitch = 0;
                if (a == Activity.Sneak) { p.Pitch = -0.08; p.Crouch = 0.4; }
                if (a == Activity.Scurry) p.Pitch = -0.12;
                break;
            }

            case Activity.Look: p.Lift = 1.5; p.Pitch = 0.06; break;
            case Activity.Rest: p.Lift = -4; p.Crouch = 0.28; p.Lid = 0.35; break;
            case Activity.Groom: p.Pitch = -0.15; p.LegsFree = true; break;
            case Activity.Sleep: p.Lift = -5; p.Crouch = 0.4; p.Lid = 1; p.LegsFree = true; break;
            case Activity.Wave: p.Lift = 2; p.Pitch = 0.16; p.LegsFree = true; break;
            case Activity.Startle: p.Lift = 5 * (1 - u); p.Pitch = 0.3 * (1 - u); break;
            case Activity.Crouch: p.Pitch = -0.1; p.Crouch = 0.85; p.Wag = u > 0.3 ? 1 : 0; break;
            case Activity.Turn:
                if (gait.Preference == GaitPreference.Bouncy) p.Lift = 3 * sin1;
                else p.Crouch = 0.18 * sin1;
                break;
            case Activity.Peek: p.Lift = -1; p.Pitch = -0.38; break;
            case Activity.Stretch: p.Lift = 6 * sin1; p.Pitch = 0.22 * sin1; p.LegsFree = true; break;
            case Activity.Shake: p.Lift = 1; break;
            case Activity.Wiggle: p.Lift = 1.5; p.Wag = 1.4; break;
            case Activity.Bounce:
            {
                double env = Math.Min(1, Math.Min(8 * u, 8 * (1 - u)));
                double b = Math.Abs(Math.Sin(3 * M.Pi * u));
                p.Lift = 3.5 * b * env;
                p.Crouch = 0.3 * (1 - b) * env;
                break;
            }
            case Activity.Curious: p.Lift = 2; p.Pitch = -0.2; p.LegsFree = true; break;
            case Activity.ArmsUp: p.Lift = 2; p.Pitch = 0.22 * Math.Sin(Math.Min(2 * u, 1) * M.Pi / 2); p.LegsFree = true; break;
            case Activity.Dance: p.Lift = 1.5 + Math.Abs(Math.Sin(6 * M.Pi * u)) * 3; p.Pitch = Math.Sin(6 * M.Pi * u) * 0.08; p.Wag = 1.6; break;
            case Activity.Glance: p.Lift = 1; break;
            case Activity.Peer: p.Lift = -3; p.Pitch = u < 0.8 ? -0.42 : -0.42 * (1 - (u - 0.8) / 0.2); break;
            case Activity.Pushup: p.Lift = -4 + (1 - Math.Abs(Math.Sin(4 * M.Pi * u))) * 5; break;
            case Activity.LegStretch: p.Lift = 1; p.Pitch = -0.06; p.LegsFree = true; break;
            case Activity.Shoot: p.Lift = 1.5; p.Pitch = 0.18; p.Crouch = 0.15; p.LegsFree = true; break;
            case Activity.Eat: p.Lift = -2.5; p.Pitch = -0.16; p.Crouch = 0.15; p.LegsFree = true; break;
            case Activity.Stare: p.Lift = -1; p.Crouch = 0.12; break;
            case Activity.Drum:
            {
                double beat = (u / 0.5) % 0.5 < 0.25 ? 1 : 0;
                p.Lift = -1 - beat * 1.5;
                p.Pitch = -0.06;
                p.Crouch = 0.18;
                p.Wag = u > 0.5 && u < 0.72 ? 1.2 : 0.4;
                p.LegsFree = true;
                break;
            }
            case Activity.Greet: p.Lift = 3; p.LegsFree = true; break;
            case Activity.Peekaboo:
                p.Speed = 1.0;
                p.Lift = 0;
                break;
            case Activity.Fasten:
            {
                double dab = 0.5 + 0.5 * Math.Sin(3 * M.Pi * u);
                p.Lift = -1.5 - dab * 1.5;
                p.Pitch = 0.16 + dab * 0.1;
                p.Crouch = 0.3 + dab * 0.2;
                p.Wag = 0.8 + dab * 0.6;
                break;
            }
            case Activity.Groove: p.Lift = 0.5; p.LegsFree = true; break;
            case Activity.Watch: p.Lift = -1; p.Pitch = 0.08; p.Crouch = 0.12; p.Lid = 0.06; break;
            case Activity.Brace: p.Lift = -3.5; p.Crouch = 0.55; p.Lid = 0.45; break;
            case Activity.Bask: p.Lift = -3; p.Pitch = 0.07; p.Crouch = 0.2; p.Lid = 0.55; break;
            case Activity.Feel: p.Lift = 1; p.Pitch = -0.06; p.LegsFree = true; break;
            case Activity.Drink: p.Lift = -3.5 * sin1; p.Pitch = -0.46 * sin1; p.Crouch = 0.2 * sin1; p.LegsFree = true; break;
            case Activity.DoubleTake: p.Lift = 3 * (u < 0.45 ? 1 : 1); p.Pitch = 0.08; break;
            case Activity.Sigh:
                p.Lift = u < 0.5 ? 2.6 : -4.2;
                p.Pitch = u < 0.5 ? 0.1 : -0.1;
                p.Crouch = u < 0.5 ? 0 : 0.3;
                p.Lid = u < 0.5 ? 0 : 0.6;
                break;
            case Activity.Fidget: p.Lift = 0.6; p.LegsFree = true; break;
            case Activity.Scratch: p.Pitch = -0.1; p.LegsFree = true; break;
            case Activity.Muse: p.Lift = 1; p.Pitch = 0.04; break;
            case Activity.Spin: p.Lift = 1; p.Crouch = 0.1; break;
            default: break;
        }
        return p;
    }
}
