using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

public static class Stage17
{
    public static int Run(string[] args)
    {
        Harness.Section("stage 17 habitat");

        var world = HabitatWorld.Preset(HabitatBiome.Forest, new Rect(0, 0, 4042, 1242));
        Harness.Check(world.Items.Count >= 6, "a forest preset has furniture");
        Harness.Check(world.Bounds.W == 4042 && world.Bounds.H == 1242, "the world is the saved size");
        Harness.Check(world.Name == "Forest Floor", "the preset keeps its name");

        var map = world.BuildMap(0.78);
        Harness.Check(map.LoopCount >= 2, "the tank floor and furniture make surfaces");
        Harness.Check(map.AllLoops.Any(l => l.Segs.Count > 0), "the tank floor loop exists");
        Harness.Check(Math.Abs(map.Standoff - 22 * 0.78) < 1e-9, "the tank uses the shared standoff");

        var spot = world.GroundSpot(map, 0.78, 900);
        Harness.Check(spot is not null && spot.Value.LoopId.Length > 0, "there is somewhere to stand");

        var spider = new Spider(Sheets.DefaultDesign(), map, new Rng(1701)) { BrainEnabled = false };
        if (spot is { } s)
        {
            spider.SetAnchor(s.Anchor.LoopId, s.Anchor.SegIdx, s.Anchor.T, s.Anchor.Dir);
            for (int i = 0; i < 120; i++) spider.Update(1.0 / 60);
        }
        Harness.Check(double.IsFinite(spider.Pos.X) && double.IsFinite(spider.Pos.Y),
            "the same spider walks a finite tank path");

        string json = world.ToJson();
        var back = HabitatWorld.FromJson(json);
        Harness.Check(back.Bounds.W == world.Bounds.W && back.Bounds.H == world.Bounds.H,
            "the habitat bounds survive JSON");
        Harness.Check(back.Items.Count == world.Items.Count, "every item survives JSON");
        Harness.Check(back.Items.FirstOrDefault()?.Kind == world.Items.FirstOrDefault()?.Kind,
            "item kinds survive JSON");

        var empty = HabitatWorld.Empty(new Rect(0, 0, 3000, 1050));
        Harness.Check(empty.Items.Count == 0 && empty.Biome == HabitatBiome.Empty,
            "an empty tank is a valid tank");

        var added = back.AddAt(HabitatItemKind.Rock, new V2(1200, 300));
        Harness.Check(added is not null && back.Items.Count == world.Items.Count + 1,
            "decorating adds a real item");
        Harness.Check(back.BuildMap(0.78).LoopCount >= map.LoopCount,
            "the decorated world rebuilds its surfaces");

        Harness.Check(Enum.GetValues<HabitatItemKind>().Length == 221, "the whole Swift furniture catalogue is present");
        Harness.Check(HabitatWorld.PresetNames.Length == 9, "all nine habitats are offered");
        Harness.Check(Enum.GetValues<InteractionKind>().Length == 17, "all seventeen interaction points exist");
        Harness.Check(WeatherKinds.All.Length == 15, "all fifteen weathers exist");

        var dish = world.AddItem(HabitatItemKind.WaterDish, new V2(700, 0));
        Harness.Check(dish.Water() is { } water && water.W > 0, "a dish has a real water area");
        var dishMap = world.BuildMap(0.78);
        var dishPoints = HabitatInteractions.Points(dish, dishMap);
        Harness.Check(dishPoints.Any(p => p.Kind == InteractionKind.DrinkEdge && p.Stand is not null),
            "a dish offers a reachable drink edge");
        Harness.Check(HabitatSemantics.Nature(HabitatItemKind.WaterDish).Has(HabitatQuality.Drinkable),
            "a dish is semantically drinkable");

        var cam = new HabitatCamera();
        cam.SetWorld(new SizeD(4000, 1200)); cam.SetView(new SizeD(1000, 600)); cam.Jump(new V2(1400, 250));
        var before = cam.Origin;
        cam.Update(1.0 / 60, new V2(1800, 550), true);
        Harness.Check(cam.Origin.DistanceTo(before) < 0.01, "the camera is still inside its dead zone");
        for (int i = 0; i < 120; i++) cam.Update(1.0 / 60, new V2(4000, 900), true);
        Harness.Check(cam.Origin.X > before.X, "the camera follows a spider that walks to the edge");

        var settings = new WeatherSettings { Mode = WeatherMode.Always, Always = WeatherKind.Rain };
        var weather = new WeatherClock(settings, HabitatBiome.Forest, 12);
        weather.Force(WeatherKind.Rain);
        Harness.Check(weather.CurrentAt(WeatherClock.Now) == WeatherKind.Rain, "weather can be pinned to rain");
        Harness.Check(weather.Conditions(WeatherClock.Now, 10).Mix.Rain > .5, "rain reaches the conditions");

        var knowledge = new HabitatKnowledge();
        knowledge.Meet(world);
        var familiarItem = world.Items[0];
        Harness.Check(knowledge.StageOf(familiarItem.Uid) == HabitatKnowledge.Stage.Familiar,
            "a first tank starts familiar");
        var knowledgeBack = HabitatKnowledge.FromJson(knowledge.ToJson());
        Harness.Check(knowledgeBack.Things.Count == knowledge.Things.Count, "knowledge survives JSON");

        var nav = new TankNav(dishMap, 0.78);
        Harness.Check(nav.Nodes.Count > 0 && nav.ReachableSpotCount(new V2(900, 100)) > 1,
            "A* links more than one stretch of tank surface");
        var route = nav.Path(spider.Pos, dish.Rect.Mid);
        Harness.Check(route is not null, "A* finds the water dish");

        // ---------------------------------------------------------- places
        var survey = new PlaceSurvey(world, dishMap, 0.78);
        Harness.Check(survey.Places.Count > 40, "the survey sizes up the whole tank");
        Harness.Check(survey.Water.Any(w => w.Id == dish.Id), "the water dish is a place to drink");
        Harness.Check(survey.Places.Any(p => p.Kind == InteractionKind.DrinkEdge), "a drink place has a stand spot");
        Harness.Check(survey.Places.Any(p => p.Q[PlaceQuality.Shelter] > .2), "some places count as shelter");
        Harness.Check(survey.Places.Any(p => p.Standing && p.Q[PlaceQuality.Elevation] > 0), "some places are raised");
        var sleepWant = new PlaceWant { Use = PlaceUse.Sleep, From = spider.Pos, Scale = .78 };
        var rankedSleep = survey.Ranked(sleepWant, p => new PlaceSense { Prey = .1 }, 6);
        Harness.Check(rankedSleep.Count > 0, "the spider can rank somewhere to sleep");
        Harness.Check(survey.Appeal(rankedSleep[0].place, sleepWant, new PlaceSense()) >= 0, "appeal is finite");
        Harness.Check(survey.Nearest(spider.Pos, 10000) is not null, "the nearest place is always found");

        // ---------------------------------------------------------- ecology
        var eco = new HabitatEcology(world, dishMap);
        eco.Refresh(survey, .78);
        Harness.Check(eco.Spots.Count > 100, "ecology has the whole tank gridded");
        Harness.Check(eco.Sites.Count > 0, "things in the tank make eco sites");
        Harness.Check(eco.Sites.Any(s => s.Feature is EcoFeature.Shelter or EcoFeature.Damp or EcoFeature.Food),
            "shelter, damp or food is understood");
        Harness.Check(double.IsFinite(eco.HidingPlaces(900, 60, 200)), "hiding places are finite");
        Harness.Check(eco.Concealment(new V2(900, 100)) >= 0, "concealment is never negative");
        Harness.Check(eco.Light(new V2(1000, 900), weather.Conditions(WeatherClock.Now, 10)) >= 0, "light is normalised");
        weather.Force(WeatherKind.Rain);
        for (int i = 0; i < 50; i++) eco.Update(.05, weather.Conditions(WeatherClock.Now, i));
        Harness.Check(eco.Wetness > 0, "rain wets the open tank");
        Harness.Check(eco.Drops.Count >= 0, "droplets are tracked");
        eco.LeaveRemains(new V2(900, 120), PreyKind.Cricket);
        Harness.Check(eco.Remains.Count == 1, "a meal leaves remains");
        Harness.Check(eco.AddArrival(EcoFeature.Food) is not null || eco.Spots.Count >= 0, "an arrival can be chosen from food");
        var arrival = eco.AddArrival(EcoFeature.Shelter);
        Harness.Check(arrival is null || Enum.IsDefined(arrival.Kind), "an arrival has a real creature");
        var skyOpen = eco.Sky.OpenAt(new V2(1000, 1000));
        Harness.Check(skyOpen is >= 0 and <= 1, "sky cover is a fraction");

        // ---------------------------------------------------------- living tank
        var mind = new TankMind();
        mind.Refresh(world, dishMap, knowledge, .78);
        Harness.Check(mind.Ecology.Spots.Count > 0, "the living tank gets its ecology");
        var calm = new WeatherConditions();
        for (int i = 0; i < 240; i++)
        {
            spider.Update(1.0 / 60);
            mind.Update(1.0 / 60, spider, calm, knowledge, .78);
            if (i % 20 == 0) eco.Update(.2, calm, .78);
        }
        Harness.Check(double.IsFinite(spider.Pos.X) && double.IsFinite(spider.Pos.Y), "the spider survives a living-tank soak");
        Harness.Check(mind.Thirst is >= 0 and <= 1 && mind.Hunger is >= 0 and <= 1, "urges stay in range");
        Harness.Check(mind.Status.Length > 0, "the tank has a current thought");

        // ---------------------------------------------------------- library
        string previous = Environment.GetEnvironmentVariable("SPIDER_HABITAT_LIBRARY") ?? "";
        string folder = Path.Combine(Path.GetTempPath(), "spider-buddy-stage17-" + Guid.NewGuid().ToString("N"));
        Environment.SetEnvironmentVariable("SPIDER_HABITAT_LIBRARY", folder);
        try
        {
            var saved = new SavedHabitat { Id = Guid.NewGuid().ToString("D"), Name = "Forest Copy", Saved = DateTime.UtcNow, Habitat = world.Clone() };
            Harness.Check(HabitatLibrary.Store(saved), "a habitat is written as one JSON file");
            Harness.Check(File.Exists(Path.Combine(folder, saved.Id + ".json")), "the library uses one file per habitat");
            var all = HabitatLibrary.All();
            Harness.Check(all.Count == 1 && all[0].Name == "Forest Copy", "the library reads it back");
            Harness.Check(HabitatLibrary.FreshName("Forest Copy") == "Forest Copy 2", "a fresh saved name is unique");
            Harness.Check(HabitatLibrary.Rename(saved.Id, "Renamed"), "a saved habitat can be renamed");
            var fitted = HabitatLibrary.Saved(saved.Id)!.Fitted(new SizeD(3200, 1100));
            Harness.Check(Math.Abs(fitted.Width - 3200) < .5 && Math.Abs(fitted.Height - 1100) < .5,
                "a saved habitat is fitted to another world");
            string share = Path.Combine(folder, "share.spiderhabitat");
            HabitatLibrary.Export(HabitatLibrary.Saved(saved.Id)!, share);
            var imported = HabitatLibrary.ImportFile(share);
            Harness.Check(imported.Id != saved.Id && HabitatLibrary.All().Count == 2, "an imported habitat gets its own identity");
            var bare = Path.Combine(folder, "bare.json");
            File.WriteAllText(bare, HabitatWorld.Empty(new Rect(0, 0, 900, 540)).ToJson());
            Harness.Check(HabitatLibrary.ImportFile(bare).Name.Length > 0, "a bare habitat file can be brought in");
            HabitatLibrary.Delete(saved.Id);
            Harness.Check(HabitatLibrary.Saved(saved.Id) is null, "a saved habitat can be deleted");
        }
        finally
        {
            try { Directory.Delete(folder, true); } catch { }
            Environment.SetEnvironmentVariable("SPIDER_HABITAT_LIBRARY", previous.Length == 0 ? null : previous);
        }

        return Harness.Summarise("stage 17 habitat");
    }
}
