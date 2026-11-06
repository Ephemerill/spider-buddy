namespace SpiderBuddy.Core;

/// <summary>
/// The spider's life in the tank: it reads the places and the weather, gets a
/// want, plans a way there and does the thing when it arrives. This is the
/// side-on equivalent of the Swift habitat's errand/inquiry machinery.
/// </summary>
public sealed class TankMind
{
    readonly Rng _rng = new(0xC0FFEE);
    HabitatWorld _world = null!;
    SurfaceMap _map = null!;
    double _scale = .78;
    HabitatKnowledge _knowledge = new();
    public HabitatEcology Ecology { get; private set; } = null!;
    public PlaceSurvey? Survey { get; private set; }
    public TankNav? Nav { get; private set; }
    public HabitatPlace? Current { get; private set; }
    public PlaceUse? Doing { get; private set; }
    public string Status { get; private set; } = "";
    public double Wet { get; private set; }
    public double Chill { get; private set; }
    public bool Sheltered { get; private set; }
    public double Thirst { get; private set; } = .25;
    public double Sleepiness { get; private set; } = .1;
    public double Hunger { get; private set; } = .3;
    public bool Busy => Current is not null || _actLeft > 0;

    double _idleIn = 2, _actLeft, _stepClock, _weatherClock;
    int _pathIndex;
    List<Spot> _path = new();
    PlaceUse _use;
    V2 _lastPos;
    public int Visits { get; private set; }

    public void Refresh(HabitatWorld world, SurfaceMap map, HabitatKnowledge knowledge, double scale)
    {
        _world = world; _map = map; _knowledge = knowledge; _scale = scale;
        Survey = new PlaceSurvey(world, map, scale);
        Ecology = new HabitatEcology(world, map);
        Ecology.Refresh(Survey, scale);
        Nav = new TankNav(map, scale);
        Current = null; _path = new(); _actLeft = 0; Status = "looking around";
    }

    public void Update(double dt, Spider spider, WeatherConditions weather, HabitatKnowledge knowledge, double scale)
    {
        if (Survey is null || Nav is null) Refresh(_world!, _map!, knowledge, scale);
        _knowledge = knowledge;
        knowledge.Clock += dt;
        dt = Math.Clamp(dt, 0, .08);

        bool open = Ecology.Sky.OpenAt(spider.Pos) > .42;
        Sheltered = !open;
        _weatherClock -= dt;
        if (_weatherClock <= 0)
        {
            _weatherClock = .3;
            double rain = weather.Mix.Rain + weather.Mix.Hail * .8 + weather.Mix.Snow * .5;
            if (open && rain > .04) Wet = Math.Min(1, Wet + rain * dt * .45);
            else Wet = Math.Max(0, Wet - dt * (.015 + (Sheltered ? .04 : 0) + weather.Mix.Sun * .05));
            double cold = weather.Mix.Cold + weather.Mix.Wind * .15 + Wet * .2;
            Chill = M.Approach(Chill, Math.Min(1, cold * (Sheltered ? .55 : 1)), .35, dt);
            if (Wet > .12) Ecology.AddDroplets(.15, spider.Pos, 26 * scale);
            if (Wet > .55 && _rng.Chance(dt * .2)) { Ecology.ShakeDrops(spider.Pos, 34 * scale, 1); Wet *= .7; }
        }

        Thirst = M.Clamp01(Thirst + dt / 240);
        Sleepiness = M.Clamp01(Sleepiness + dt / 420);
        Hunger = M.Clamp01(Hunger + dt / 300);
        if (spider.Fed > .45) Hunger = Math.Max(0, Hunger - dt * .08);

        if (spider.PreyHunt != HuntStage.None) return;
        if (Current is { } c && c.Anchor.IsValid)
        {
            if (_pathIndex > 0) Move(dt, spider);
            else Act(dt, spider, weather);
            return;
        }
        _idleIn -= dt;
        if (_idleIn > 0) return;
        _idleIn = 3 + _rng.Range(0, 7);

        if (weather.Mix.Rain > .25 && !Sheltered && Wet > .25 && _rng.Chance(.7)) { Seek(PlaceUse.Shelter, spider); return; }
        if (Chill > .6 && _rng.Chance(.6)) { Seek(PlaceUse.Shelter, spider); return; }
        if (weather.Mix.Heat > .5 && open && _rng.Chance(.5)) { Seek(PlaceUse.Hide, spider); return; }
        if (Sleepiness > .7 && (weather.Mix.Night > .2 || _rng.Chance(.25))) { Seek(PlaceUse.Sleep, spider); return; }
        if (Thirst > .6) { Seek(PlaceUse.Drink, spider); return; }
        if (Hunger > .55 && _rng.Chance(.65)) { Seek(PlaceUse.Hunt, spider); return; }
        if (weather.Mix.Sun > .35 && open && _rng.Chance(.4 * (1.2 - spider.Design.Personality.Laziness))) { Seek(PlaceUse.Bask, spider); return; }
        if (_rng.Chance(.25)) { Seek(_rng.Chance(.4) ? PlaceUse.Lookout : (_rng.Chance(.5) ? PlaceUse.Rest : PlaceUse.Perch), spider); return; }
        if (_rng.Chance(.2)) { Seek(PlaceUse.Shelter, spider); return; }
        Status = "watching the tank";
        spider.Play(Activity.Look, 2);
    }

    void Seek(PlaceUse use, Spider spider)
    {
        if (Survey is null || Nav is null) return;
        var personality = spider.Design.Personality;
        var want = new PlaceWant
        {
            Use = use, From = spider.Pos, Scale = _scale, Personality = personality,
            Threat = Wet > .5 ? new V2(spider.Pos.X, spider.Pos.Y + 80) : null,
            Rough = Wet > .5, Sun = 0
        };
        var ranked = Survey.Ranked(want, pl =>
        {
            var rec = _knowledge.Places.TryGetValue(pl.Key, out var r) ? r : null;
            double thingFond = 0;
            if (pl.Owner != 0)
            {
                var uid = Survey.OwnerUid(pl.Owner);
                if (uid.Length > 0) thingFond = _knowledge.For(uid).Fond;
            }
            return new PlaceSense
            {
                Record = rec, ThingFond = thingFond,
                Disturbance = 0,
                Warm = Ecology.Warmth,
                Prey = Ecology.PreyPull(pl.Point, _scale)
            };
        }, 10);
        if (ranked.Count == 0)
        {
            // Nothing suitable: stay put and do something small.
            spider.Play(use == PlaceUse.Sleep ? Activity.Rest : Activity.Look, 3);
            _idleIn = 4;
            return;
        }
        var candidates = new List<(HabitatPlace place, List<Spot> path, double score)>();
        for (int i = 0; i < ranked.Count && candidates.Count < 4; i++)
        {
            var pl = ranked[i].place;
            var path = Nav.Path(spider.Pos, pl.Point);
            if (path is not null) candidates.Add((pl, path, ranked[i].score));
            else if (pl.Anchor.IsValid) candidates.Add((pl, new List<Spot>(), ranked[i].score));
        }
        if (candidates.Count == 0) { _idleIn = 5; return; }
        var pick = candidates[_rng.WeightedIndex(candidates.Select(c => c.score).ToList())];
        Start(pick.place, pick.path, use, spider);
    }

    void Start(HabitatPlace place, List<Spot> path, PlaceUse use, Spider spider)
    {
        Current = place; _use = use; _path = path; _pathIndex = 0; _stepClock = 0;
        _lastPos = spider.Pos;
        Status = use switch
        {
            PlaceUse.Drink => "off for a drink", PlaceUse.Shelter => "getting out of the weather",
            PlaceUse.Hide => "finding somewhere to hide", PlaceUse.Sleep => "looking for somewhere to sleep",
            PlaceUse.Rest => "going somewhere quiet", PlaceUse.Bask => "going to bask",
            PlaceUse.Lookout => "climbing for a look out", PlaceUse.Hunt => "following a smell",
            _ => "going to have a look"
        };
        _pathIndex = path.Count > 1 ? 1 : 0;
    }

    void Move(double dt, Spider spider)
    {
        _stepClock -= dt;
        if (_stepClock > 0) return;
        _stepClock = .18;
        if (_pathIndex >= _path.Count)
        {
            if (Current is { } place)
            {
                if (place.Anchor.IsValid) spider.SetAnchor(place.Anchor.LoopId, place.Anchor.SegIdx, place.Anchor.T, (int)place.Along);
                _pathIndex = 0;
                _actLeft = .01;
                spider.Play(Activity.Idle, .3);
            }
            return;
        }
        var spot = _path[_pathIndex++];
        spider.SetAnchor(spot.Anchor.LoopId, spot.Anchor.SegIdx, spot.Anchor.T, 1);
        spider.Play(Activity.Walk, .4);
        if (_pathIndex >= _path.Count && Current is { } c)
        {
            if (c.Anchor.IsValid) spider.SetAnchor(c.Anchor.LoopId, c.Anchor.SegIdx, c.Anchor.T, (int)c.Along);
            _pathIndex = 0; _stepClock = .16;
        }
    }

    double _actionStartWeather;

    void Act(double dt, Spider spider, WeatherConditions weather)
    {
        if (Current is null) return;
        if (_actLeft <= 0)
        {
            var place = Current;
            _knowledge.VisitPlace(place.Key, place.Point, place.Owner == 0 ? null : Survey!.OwnerUid(place.Owner), 0, _use.Key());
            if (place.Thing != 0 && _world.Items.FirstOrDefault(i => i.Id == place.Thing) is { } item)
            {
                _knowledge.Expose(item, .12);
                _knowledge.Warm(item, .06);
            }
            _actionStartWeather = weather.Mix.Rain;
            switch (_use)
            {
                case PlaceUse.Sleep:
                    spider.Play(Activity.Sleep, 26);
                    _actLeft = 26; Sleepiness = Math.Max(0, Sleepiness - .8); Status = "asleep"; break;
                case PlaceUse.Rest:
                    spider.Play(Activity.Rest, 9); _actLeft = 9; Status = "resting"; break;
                case PlaceUse.Shelter:
                    spider.Play(spider.ShelterPose(weather, _rng), 8); _actLeft = 8;
                    Status = "sheltering"; break;
                case PlaceUse.Hide:
                    spider.Play(Activity.Crouch, 7); _actLeft = 7; Status = "keeping out of sight"; break;
                case PlaceUse.Drink:
                    spider.Play(Activity.Drink, 5); _actLeft = 5; Thirst = 0; Status = "drinking"; break;
                case PlaceUse.Bask:
                    spider.Play(Activity.Bask, 12); _actLeft = 12; Status = "basking"; break;
                case PlaceUse.Lookout:
                    spider.Play(Activity.Watch, 10); _actLeft = 10; Status = "on the lookout"; break;
                case PlaceUse.Hunt:
                    spider.Play(Activity.Look, 3); _actLeft = 3; Status = "hunting";
                    if (spider.LoosePrey == 0)
                    {
                        var prey = spider.ReleasePrey(Prey.WanderingIn(false, weather.Mix.Rain > .1, _rng),
                            place.Focus ?? place.Point + new V2(0, 25 * _scale));
                        if (prey is not null) { spider.StartHunt(prey); Hunger = Math.Max(0, Hunger - .45); }
                    }
                    break;
                default:
                    spider.Play(PlaceUseActivity(place, _use), 7); _actLeft = 7;
                    Status = $"at the {ItemLabel(place)}"; break;
            }
            if (_use != PlaceUse.Sleep && _use != PlaceUse.Hunt) Visits++;
            return;
        }
        _actLeft -= dt;
        if (_actLeft <= 0)
        {
            Current = null; Doing = null; Status = "looking around";
            _idleIn = 7 + _rng.Range(0, 14);
            _knowledge.Dirty = true;
        }
    }

    static Activity PlaceUseActivity(HabitatPlace place, PlaceUse use) => use switch
    {
        PlaceUse.Perch => place.Hanging ? Activity.Cling : Activity.Look,
        _ => Activity.Look
    };

    string ItemLabel(HabitatPlace place)
    {
        if (place.Thing == 0) return "glass";
        var item = _world.Items.FirstOrDefault(i => i.Id == place.Thing);
        return item?.Kind.Label().ToLowerInvariant() ?? "place";
    }

    /// <summary>A prey animal has appeared or is being released: go and see.</summary>
    public bool TakeInterest(V2 at, Spider spider)
    {
        if (Current is not null || Survey is null) return false;
        var place = Survey.Nearest(at, 220 * _scale);
        if (place is null) return false;
        var path = Nav?.Path(spider.Pos, place.Point) ?? new List<Spot>();
        Start(place, path, PlaceUse.Hunt, spider);
        return true;
    }
}

static class ShelterActivity
{
    public static Activity ShelterPose(this Spider spider, WeatherConditions weather, Rng rng)
        => weather.Mix.Cold > .3 ? Activity.Rest : (rng.Chance(.5) ? Activity.Crouch : Activity.Peek);
}
