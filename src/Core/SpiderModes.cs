namespace SpiderBuddy.Core;

/// <summary>Where the spider is: on a surface, hanging from silk, or in free flight (spec 7).</summary>
public enum Mode
{
    Attached,   // standing/walking on a surface
    Dangling,   // hanging from its silk
    Air,        // falling or swinging free
    Held,       // carried at the pointer's grab offset
    Clinging,   // hanging off the pointer by its front legs (spec 5.5)
}

/// <summary>What kind of airborne moment it is (spec 7).</summary>
public enum AirKind
{
    Fall,
    Rappel,
    Swing,
    Climb,
    Mantle,
    Leap,
    Thrown,
}
