import AppKit

// MARK: - What each kind of thing is
//
// Everything about a kind of thing in the tank that is not its picture
// lives in its definition, in one place: what it is called, which part of
// the picker it goes in, how big it comes, where it may be put, how it
// moves in the air, and — most of all — its physical shape: the parts of
// it the spider can really hold on to (see HabitatGeometry.swift).
//
// Adding a kind of thing: a case below, its definition in `definition`,
// its shape (built from the same paths its picture is painted from, in
// `HabitatShape`), and its picture in `HabitatArt.paintItem`. The compiler
// asks for each in turn. `tools/perch.sh sheet` draws every kind with its
// shape over its picture, to check the two agree.

/// Things to put in the habitat. Some are furniture it can climb on; some
/// are just scenery; some are the pieces structures are built from, and
/// what holds them up (see HabitatStructures.swift).
enum HabitatItemKind: String, Codable, CaseIterable {
    // Perches.
    case log, branch, driftwood, corkBark, hide, rock, boulder, bamboo, cactus, plant, vine, waterDish
    // Plants and details.
    case fern, grass, flower, succulent, mushrooms, moss, leafPile, pebbles, twigs, crystal
    // Structures: branches, roots, driftwood, bamboo, stems.
    case thinBranch, mediumBranch, thickBranch, shortBranch, longBranch, forkedBranch, yBranch, crookedBranch
    case twig, root, climbingRoot, driftwoodArch, driftwoodSnag, bambooPole, bambooSegment, driedStem
    // Bark and platforms.
    case corkSlab, corkTube, barkLedge, slateLedge
    // Vines.
    case thickVine, thinVine
    // Supports: hardware, fixed to the back wall or standing, mostly behind.
    case brace, branchBracket, wallAnchor, glassMount, suctionCup, verticalSupport, horizontalSupport, crossBrace
    case hangingHook, vineClip, shelfBracket
    // More supports at the back: a batten, a steel channel, an angle bracket.
    case wallRail, metalStrut, angleBracket
    // Built: made by hand from what a workshop has — sawn timber, board,
    // dowel, pipe, brick — for a tank that looks put together by its keeper.
    case beam, post, plank, plywood, dowel, ladder, pipe, brick, woodBlock, crate, rope, backPanel, pegboard
    // Building: a house for it — floors, solid walls, a roof, stairs, and
    // doors and windows that open and close.
    case floorboards, wall, door, doorClosed, window, windowOpen, gableRoof, stairs, kneeBrace, fence
    // Backing walls: behind the rooms, like the back wall of a room.
    case woodBacking, brickBacking, stoneBacking, logBacking, wallpaper, backWindow
    // Home: things to live with.
    case bed, table, chair, bookshelf, sofa, fireplace, floorLamp, hangingLamp, lantern, candle, stringLights
    case rug, picture, clock, houseplant, spool, teacup, flowerBox, sign
    case armchair, desk, dresser, wardrobe, bunkBed, piano, stove, fridge, counter, bathtub, chest, coatRack, beanbag
    // Decor: the small things that make it a home, and what hangs on the walls.
    case tv, radio, laptop, recordPlayer, globe, vase, bookStack, flyJar, trophy
    case painting, poster, mirror, curtains, dartboard, wallShelf, sconce, chandelier
    // Natural bracing: a stake with a fork at the top to hold a branch.
    case stake
    // A natural world (HabitatNature.swift). Structures: branches, roots,
    // driftwood, bark, bamboo, hanging things, platforms, rock.
    case twistedBranch, threeFork, exposedRoot, rootTangle, stump, driftwoodRoot, driftwoodBranch, corkTunnel, leaningBark
    case bambooTipi, hangingBranch, lianaLoop, hangingRoots, stickRaft, mossPlatform, rockSpire, stoneArch
    // Shelters: covered places it can really get into.
    case barkCave, rockCrevice, logDen, curledLeafHide, leafCanopy, rootHollow, mossyHide, hangingLeafShelter, overhang
    // Plants.
    case smallFern, largeFern, broadLeaf, trailingPlant, climbingVine, grassClump, floweringPlant, tinyFlowers, aloe, jadePlant
    case lithops, airPlant, miniPalm, deadPlant, fiddleheads, creepingCover, hangingFoliage, mossCushion
    // The ground.
    case gravel, sandDrift, pineNeedles
    // Natural details.
    case mushroom, mushroomCluster, tinyMushrooms, glowMushrooms, shelfFungus, lichen, acorn, seedPod, pineCone, seaShell
    case snailShell, fallenLeaf, curledLeaf, deadLeaf, leafHeap, pebblePile, smoothStones, crystalCluster, petals, puddle, shedBark, twigPile
    // Things for something: water, food, warmth, a view, silk, climbing, damp, cover.
    case rockPool, feedingPlatform, baskingStone, lookout, silkFrame, climbingBark, moistMoss, shelterCanopy
    // Loose: small and light enough to be blown or nudged about (see `LooseBody`).
    case looseLeaf, petal, tinyTwig, feather, seed, smallShell, tinyPebble

    /// Everything about it but its picture. (Made once for each kind.)
    var definition: HabitatObjectDefinition { HabitatItemKind.definitions[self]! }

    private static let definitions: [HabitatItemKind: HabitatObjectDefinition] = Dictionary(uniqueKeysWithValues: allCases.map { k in
        var d = k.made
        d.group = k.group
        d.traits = k.traits
        return (k, d)
    })

    private var made: HabitatObjectDefinition {
        typealias D = HabitatObjectDefinition
        let pieces = HabitatShape.pieceShape(self), joints = HabitatShape.piecePorts(self)
        switch self {
        case .log: return D("Log", .perch, 180, 50, .rests, shelf: .structures, shape: HabitatShape.log)
        case .branch: return D("Branch", .perch, 230, 130, .wedged, shelf: .structures, shape: HabitatShape.branch, ports: joints)
        case .driftwood: return D("Driftwood", .perch, 200, 56, .rests, shelf: .structures, shape: HabitatShape.driftwood)
        case .corkBark: return D("Cork Bark", .perch, 74, 210, .ground, shelf: .structures, shadow: 0.8, shape: HabitatShape.corkBark)
        case .hide: return D("Hollow Log", .perch, 130, 66, .ground, shelf: .structures, shape: HabitatShape.hollowLog)
        case .rock: return D("Rock", .perch, 76, 44, .ground, shelf: .structures, shape: HabitatShape.rock)
        case .boulder: return D("Boulder", .perch, 140, 92, .ground, shelf: .structures, shape: HabitatShape.rock)
        case .bamboo: return D("Bamboo", .perch, 60, 250, .ground, shelf: .structures, sway: 0.012, windLean: 0.035, shadow: 0.8, shape: HabitatShape.bamboo)
        case .cactus: return D("Cactus", .perch, 70, 150, .ground, shelf: .plants, shadow: 0.8, shape: HabitatShape.cactus)
        case .plant: return D("Leafy Plant", .perch, 120, 150, .rests, shelf: .plants, sway: 0.018, windLean: 0.05, shadow: 0.5, shape: HabitatShape.plant)
        case .vine: return D("Hanging Vine", .perch, 40, 230, .hangs, shelf: .structures, stretch: .vertical, sway: 0.05, windLean: 0.14,
                             snow: .bare, shape: HabitatShape.vine, ports: joints)
        case .waterDish: return D("Water Dish", .perch, 96, 26, .ground, shelf: .functional, snow: .bare, shape: HabitatShape.waterDish)
        case .fern: return D("Fern", .scenery, 130, 90, .rests, sway: 0.035, windLean: 0.1, shadow: 0.6, shape: HabitatShape.fern)
        case .grass: return D("Tall Grass", .scenery, 90, 84, .rests, sway: 0.035, windLean: 0.16, shadow: 0.6, shape: HabitatShape.grass)
        case .flower: return D("Flowers", .scenery, 80, 80, .rests, sway: 0.035, windLean: 0.13, shadow: 0.6, shape: HabitatShape.flowers)
        case .succulent: return D("Succulent", .scenery, 64, 46, .rests, shape: HabitatShape.succulent)
        case .mushrooms: return D("Mushrooms", .scenery, 66, 46, .rests, shelf: .details, shape: HabitatShape.mushrooms)
        case .moss: return D("Moss", .scenery, 120, 24, .rests, shelf: .ground, shape: HabitatShape.groundCover)
        case .leafPile: return D("Leaf Litter", .scenery, 130, 26, .rests, shelf: .ground, shape: HabitatShape.groundCover)
        case .pebbles: return D("Pebbles", .scenery, 90, 20, .rests, shelf: .ground, shape: HabitatShape.groundCover)
        case .twigs: return D("Twigs", .scenery, 96, 30, .rests, shelf: .ground, shape: HabitatShape.groundCover)
        case .crystal: return D("Crystals", .scenery, 64, 70, .rests, shelf: .details, shape: HabitatShape.crystals)

        case .thinBranch: return D("Thin Branch", .perch, 200, 56, .wedged, shelf: .structures, snow: .tops(0.6), shape: pieces, ports: joints)
        case .mediumBranch: return D("Medium Branch", .perch, 240, 80, .wedged, shelf: .structures, snow: .tops(0.75), shape: pieces, ports: joints)
        case .thickBranch: return D("Thick Branch", .perch, 280, 100, .wedged, shelf: .structures, shape: pieces, ports: joints)
        case .shortBranch: return D("Short Branch", .perch, 120, 44, .wedged, shelf: .structures, snow: .tops(0.7), shape: pieces, ports: joints)
        case .longBranch: return D("Long Branch", .perch, 440, 120, .wedged, shelf: .structures, snow: .tops(0.75), shape: pieces, ports: joints)
        case .forkedBranch: return D("Forked Branch", .perch, 240, 140, .wedged, shelf: .structures, snow: .tops(0.75), shape: pieces, ports: joints)
        case .yBranch: return D("Y Branch", .perch, 150, 210, .wedged, shelf: .structures, snow: .tops(0.7), shape: pieces, ports: joints)
        case .crookedBranch: return D("Crooked Branch", .perch, 250, 120, .wedged, shelf: .structures, snow: .tops(0.7), shape: pieces, ports: joints)
        case .twig: return D("Twig", .perch, 90, 34, .wedged, shelf: .structures, snow: .tops(0.4), shape: pieces, ports: joints)
        case .root: return D("Root", .perch, 230, 70, .rests, shelf: .structures, shape: pieces, ports: joints)
        case .climbingRoot: return D("Climbing Root", .perch, 80, 280, .rests, shelf: .structures, stretch: .vertical, shadow: 0.5,
                                     snow: .tops(0.7), shape: pieces, ports: joints)
        case .driftwoodArch: return D("Driftwood Arch", .perch, 260, 120, .rests, shelf: .structures, shadow: 0.9, shape: pieces, ports: joints)
        case .driftwoodSnag: return D("Driftwood Snag", .perch, 170, 230, .rests, shelf: .structures, shadow: 0.45, snow: .tops(0.8), shape: pieces, ports: joints)
        case .bambooPole: return D("Bamboo Pole", .perch, 22, 320, .rests, shelf: .structures, stretch: .vertical, shadow: 1.6,
                                   snow: .tops(0.6), shape: pieces, ports: joints)
        case .bambooSegment: return D("Bamboo Piece", .perch, 170, 22, .wedged, shelf: .structures, stretch: .horizontal,
                                      snow: .tops(0.7), shape: pieces, ports: joints)
        case .driedStem: return D("Dried Stem", .perch, 60, 230, .rests, shelf: .structures, stretch: .vertical, sway: 0.01, windLean: 0.05,
                                  shadow: 0.3, snow: .bare, shape: pieces, ports: joints)

        case .corkSlab: return D("Cork Slab", .perch, 190, 46, .wedged, shelf: .structures, snow: .tops(1), shape: pieces, ports: joints)
        case .corkTube: return D("Cork Tube", .perch, 90, 200, .rests, shelf: .structures, stretch: .vertical, shadow: 0.9, snow: .tops(0.8), shape: pieces, ports: joints)
        case .barkLedge: return D("Bark Ledge", .perch, 170, 30, .wedged, shelf: .structures, snow: .tops(1), shape: pieces, ports: joints)
        case .slateLedge: return D("Slate Shelf", .perch, 160, 24, .wedged, shelf: .structures, snow: .tops(1), shape: pieces, ports: joints)

        case .thickVine: return D("Thick Vine", .perch, 260, 90, .wedged, shelf: .structures, stretch: .horizontal, snow: .tops(0.5), shape: pieces, ports: joints)
        case .thinVine: return D("Thin Vine", .perch, 36, 170, .hangs, shelf: .structures, stretch: .vertical, sway: 0.05, windLean: 0.16,
                                 snow: .bare, shape: pieces, ports: joints)

        case .brace: return D("Back Brace", .perch, 30, 170, .wedged, shelf: .supports, layer: .rear, mount: .wall, stretch: .vertical,
                              snow: .bare, note: "A strut fixed to the back wall, with a cup at the top to lay a branch in", shape: pieces, ports: joints)
        case .branchBracket: return D("Branch Bracket", .scenery, 40, 44, .wedged, shelf: .supports, layer: .rear, mount: .wall,
                                      snow: .bare, note: "A small bracket on the back wall that holds a branch in its cup", shape: pieces, ports: joints)
        case .wallAnchor: return D("Wall Anchor", .scenery, 20, 20, .wedged, shelf: .supports, layer: .rear, mount: .wall,
                                   snow: .bare, note: "A fixing in the back wall: the end of a branch or a post goes right into it", shape: pieces, ports: joints)
        case .glassMount: return D("Glass Mount", .scenery, 70, 30, .wedged, shelf: .supports, layer: .rear, mount: .wall,
                                   snow: .bare, note: "A clear ledge stuck to the back glass, to rest things on", shape: pieces, ports: joints)
        case .suctionCup: return D("Suction Cup", .scenery, 26, 34, .wedged, shelf: .supports, layer: .rear, mount: .wall,
                                   snow: .bare, note: "A suction-cup mount with a clip: lay a branch in it, or hang a vine from it", shape: pieces, ports: joints)
        case .verticalSupport: return D("Back Post", .perch, 14, 210, .rests, shelf: .supports, layer: .rear, stretch: .vertical, shadow: 1.4,
                                        snow: .bare, note: "A wooden post behind things: stands on the ground, or on something, and holds things up on its top", shape: pieces, ports: joints)
        case .horizontalSupport: return D("Crossbar", .perch, 210, 12, .wedged, shelf: .supports, layer: .rear, stretch: .horizontal,
                                          snow: .bare, note: "A horizontal support: its ends fasten to uprights or anchors; rest things on it", shape: pieces, ports: joints)
        case .crossBrace: return D("Cross Brace", .perch, 120, 120, .wedged, shelf: .supports, layer: .rear, mount: .wall,
                                   snow: .bare, note: "Two rods crossed, fixed to the back wall", shape: pieces, ports: joints)
        case .hangingHook: return D("Hanger", .perch, 16, 90, .hangs, shelf: .supports, layer: .rear, stretch: .vertical, sway: 0.02, windLean: 0.06,
                                    snow: .bare, note: "A hanging attachment: a cord with a hook, from the lid or a branch", shape: pieces, ports: joints)
        case .vineClip: return D("Vine Clip", .scenery, 20, 22, .hangs, shelf: .supports, layer: .rear,
                                 snow: .bare, note: "A vine attachment: clip it to a branch and hang a vine from it", shape: pieces, ports: joints)
        case .shelfBracket: return D("Shelf Bracket", .scenery, 56, 48, .wedged, shelf: .supports, layer: .rear, mount: .wall,
                                     snow: .bare, note: "A bracket on the back wall with a flat top: put a platform on two of them", shape: pieces, ports: joints)
        case .wallRail: return D("Wall Rail", .perch, 220, 14, .wedged, shelf: .supports, layer: .rear, mount: .wall, stretch: .horizontal,
                                 snow: .bare, note: "A wooden batten screwed along the back wall: hang things from it, rest things on it", shape: pieces, ports: joints)
        case .metalStrut: return D("Metal Strut", .perch, 20, 220, .wedged, shelf: .supports, layer: .rear, mount: .wall, stretch: .vertical,
                                   snow: .bare, note: "A slotted steel channel up the back wall: fasten bars and branches anywhere along it", shape: pieces, ports: joints)
        case .angleBracket: return D("Angle Bracket", .scenery, 44, 44, .wedged, shelf: .supports, layer: .rear, mount: .wall,
                                     snow: .bare, note: "A steel L on the back wall with a flat top to rest a beam or a board on", shape: pieces, ports: joints)

        case .beam: return D("2×4 Beam", .perch, 220, 20, .wedged, shelf: .built, stretch: .horizontal, snow: .tops(1),
                             note: "A length of sawn timber: lay it across uprights, or fix its ends in anchors", shape: pieces, ports: joints)
        case .post: return D("4×4 Post", .perch, 24, 220, .rests, shelf: .built, stretch: .vertical, shadow: 1.5, snow: .tops(1),
                             note: "A square wooden post: stands up, and things rest on its top", shape: pieces, ports: joints)
        case .plank: return D("Plank", .perch, 220, 11, .wedged, shelf: .built, stretch: .horizontal, snow: .tops(1),
                              note: "A thin board: a shelf across two supports", shape: pieces, ports: joints)
        case .plywood: return D("Plywood", .perch, 180, 15, .wedged, shelf: .built, stretch: .horizontal, snow: .tops(1),
                                note: "A plywood platform", shape: pieces, ports: joints)
        case .dowel: return D("Dowel", .perch, 200, 8, .wedged, shelf: .built, stretch: .horizontal, snow: .tops(0.5),
                              note: "A round wooden rod: a perch, or a rung between two uprights", shape: pieces, ports: joints)
        case .ladder: return D("Stick Ladder", .perch, 54, 180, .rests, shelf: .built, stretch: .vertical, shadow: 1.1, snow: .tops(0.5),
                               note: "A little ladder of craft sticks", shape: pieces, ports: joints)
        case .pipe: return D("Pipe", .perch, 200, 20, .wedged, shelf: .built, stretch: .horizontal, snow: .tops(0.9),
                             note: "A length of plastic pipe", shape: pieces, ports: joints)
        case .brick: return D("Brick", .perch, 64, 26, .rests, shelf: .built, snow: .tops(1), note: "Stack them into a pillar", shape: pieces, ports: joints)
        case .woodBlock: return D("Wood Block", .perch, 46, 46, .rests, shelf: .built, snow: .tops(1), note: "A block of wood: stack them", shape: pieces, ports: joints)
        case .crate: return D("Crate", .perch, 130, 92, .rests, shelf: .built, snow: .tops(1), note: "A little slatted crate", shape: pieces, ports: joints)
        case .rope: return D("Rope", .perch, 20, 200, .hangs, shelf: .built, stretch: .vertical, sway: 0.03, windLean: 0.1,
                             snow: .bare, note: "A rope from the lid or a beam, to climb", shape: pieces, ports: joints)
        case .backPanel: return D("Back Panel", .scenery, 240, 200, .wedged, shelf: .built, layer: .rear, mount: .wall,
                                  snow: .bare, note: "A board fixed to the back wall, behind everything", shape: pieces, ports: joints)
        case .pegboard: return D("Pegboard", .scenery, 200, 160, .wedged, shelf: .built, layer: .rear, mount: .wall,
                                 snow: .bare, note: "Pegboard on the back wall, behind everything", shape: pieces, ports: joints)

        case .floorboards: return D("Floorboards", .perch, 220, 14, .wedged, shelf: .building, stretch: .horizontal, snow: .tops(1),
                                    note: "A floor or a ceiling: lay it across the tops of two walls", shape: pieces, ports: joints)
        case .wall: return D("Wall", .perch, 18, 150, .rests, shelf: .building, stretch: .vertical, shadow: 1.4, snow: .tops(1),
                             note: "A solid wooden wall: stands on the ground or a floor", shape: pieces, ports: joints)
        case .door: return D("Door", .perch, 60, 150, .rests, shelf: .building, stretch: .vertical, shadow: 0.5, snow: .tops(1),
                             note: "A wall with a door in it, open — double-click it to close it", shape: pieces, ports: joints)
        case .doorClosed: return D("Door (Shut)", .perch, 60, 150, .rests, shelf: .building, stretch: .vertical, shadow: 0.5, snow: .tops(1),
                                   note: "A wall with a door in it, shut — double-click it to open it", shape: pieces, ports: joints)
        case .window: return D("Window", .perch, 44, 150, .rests, shelf: .building, stretch: .vertical, shadow: 0.5, snow: .tops(1),
                               note: "A wall with a window in it — double-click it to open it", shape: pieces, ports: joints)
        case .windowOpen: return D("Window (Open)", .perch, 44, 150, .rests, shelf: .building, stretch: .vertical, shadow: 0.5, snow: .tops(1),
                                   note: "A wall with an open window: it can climb in and out — double-click it to shut it", shape: pieces, ports: joints)
        case .gableRoof: return D("Roof", .perch, 240, 110, .wedged, shelf: .building, stretch: .horizontal, snow: .tops(1.3),
                                  note: "A pitched roof: put it on the tops of two walls", shape: pieces, ports: joints)
        case .stairs: return D("Stairs", .perch, 120, 100, .rests, shelf: .building, snow: .tops(1), note: "Steps up to the next floor", shape: pieces, ports: joints)
        case .kneeBrace: return D("Knee Brace", .perch, 60, 60, .wedged, shelf: .building,
                                  note: "A diagonal timber from a wall to under a floor or a balcony", shape: pieces, ports: joints)
        case .fence: return D("Fence", .perch, 130, 44, .rests, shelf: .building, stretch: .horizontal, snow: .tops(0.6),
                              note: "A little picket fence, or a railing", shape: pieces, ports: joints)

        case .woodBacking: return D("Wood Wall", .scenery, 220, 180, .wedged, shelf: .walls, layer: .rear, mount: .wall, stretch: .both,
                                    snow: .bare, note: "Planks behind a room, like its back wall: brackets screw into it", shape: pieces, ports: joints)
        case .brickBacking: return D("Brick Wall", .scenery, 220, 180, .wedged, shelf: .walls, layer: .rear, mount: .wall, stretch: .both,
                                     snow: .bare, note: "Brickwork behind a room", shape: pieces, ports: joints)
        case .stoneBacking: return D("Stone Wall", .scenery, 220, 180, .wedged, shelf: .walls, layer: .rear, mount: .wall, stretch: .both,
                                     snow: .bare, note: "Stonework behind a room", shape: pieces, ports: joints)
        case .logBacking: return D("Log Wall", .scenery, 220, 180, .wedged, shelf: .walls, layer: .rear, mount: .wall, stretch: .both,
                                   snow: .bare, note: "A log-cabin wall behind a room", shape: pieces, ports: joints)
        case .wallpaper: return D("Wallpaper", .scenery, 220, 180, .wedged, shelf: .walls, layer: .rear, mount: .wall, stretch: .both,
                                  snow: .bare, note: "A papered wall behind a room", shape: pieces, ports: joints)
        case .backWindow: return D("Back Window", .scenery, 70, 70, .wedged, shelf: .walls, layer: .rear, mount: .wall,
                                   snow: .bare, note: "A window in the back wall, with curtains", shape: pieces, ports: joints)

        case .bed: return D("Matchbox Bed", .perch, 96, 38, .rests, shelf: .home, snow: .tops(1), note: "A matchbox, made up as a bed", shape: pieces, ports: joints)
        case .table: return D("Table", .perch, 90, 52, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)
        case .chair: return D("Chair", .perch, 40, 64, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)
        case .bookshelf: return D("Bookshelf", .perch, 110, 170, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)
        case .sofa: return D("Sofa", .perch, 110, 50, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)
        case .fireplace: return D("Fireplace", .perch, 100, 100, .rests, shelf: .home, snow: .tops(1), note: "A hearth with a fire in it", shape: pieces, ports: joints)
        case .floorLamp: return D("Floor Lamp", .perch, 34, 110, .rests, shelf: .home, snow: .tops(0.8), shape: pieces, ports: joints)
        case .hangingLamp: return D("Hanging Lamp", .perch, 44, 120, .hangs, shelf: .home, stretch: .vertical, sway: 0.015, windLean: 0.04,
                                    snow: .bare, note: "A lamp on a cord, from the lid, a ceiling or a branch", shape: pieces, ports: joints)
        case .lantern: return D("Lantern", .perch, 30, 120, .hangs, shelf: .home, stretch: .vertical, sway: 0.02, windLean: 0.06,
                                snow: .bare, note: "A lantern on a cord, from the lid, a ceiling or a branch", shape: pieces, ports: joints)
        case .candle: return D("Candle", .perch, 20, 36, .rests, shelf: .home, snow: .bare, shape: pieces, ports: joints)
        case .stringLights: return D("String Lights", .perch, 240, 50, .wedged, shelf: .home, stretch: .horizontal, snow: .bare,
                                     note: "Fairy lights: fasten each end to something", shape: pieces, ports: joints)
        case .rug: return D("Rug", .scenery, 110, 8, .rests, shelf: .home, snow: .bare, shape: pieces, ports: joints)
        case .picture: return D("Picture", .scenery, 44, 36, .wedged, shelf: .home, layer: .rear, mount: .wall, snow: .bare,
                                note: "A little painting, hung on the back wall", shape: pieces, ports: joints)
        case .clock: return D("Clock", .scenery, 36, 36, .wedged, shelf: .home, layer: .rear, mount: .wall, snow: .bare,
                              note: "A clock on the back wall", shape: pieces, ports: joints)
        case .houseplant: return D("Houseplant", .perch, 44, 64, .rests, shelf: .home, sway: 0.012, windLean: 0.03, shadow: 0.6, shape: pieces, ports: joints)
        case .spool: return D("Spool", .perch, 40, 44, .rests, shelf: .home, snow: .tops(1), note: "A cotton reel: a stool", shape: pieces, ports: joints)
        case .teacup: return D("Teacup", .perch, 44, 30, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)
        case .flowerBox: return D("Window Box", .perch, 70, 34, .wedged, shelf: .home, snow: .tops(0.8),
                                  note: "Flowers in a box: rest it on a bracket or a sill", shape: pieces, ports: joints)
        case .sign: return D("Home Sign", .perch, 70, 60, .hangs, shelf: .home, sway: 0.01, windLean: 0.03, snow: .tops(0.6),
                             note: "A little sign that says HOME: hang it from a branch, a hook or a beam", shape: pieces, ports: joints)
        case .armchair: return D("Armchair", .perch, 64, 54, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)
        case .desk: return D("Desk", .perch, 110, 62, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)
        case .dresser: return D("Chest of Drawers", .perch, 80, 80, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)
        case .wardrobe: return D("Wardrobe", .perch, 80, 150, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)
        case .bunkBed: return D("Bunk Bed", .perch, 110, 110, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)
        case .piano: return D("Piano", .perch, 110, 90, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)
        case .stove: return D("Stove", .perch, 80, 80, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)
        case .fridge: return D("Fridge", .perch, 60, 130, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)
        case .counter: return D("Kitchen Counter", .perch, 120, 70, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)
        case .bathtub: return D("Bathtub", .perch, 130, 56, .rests, shelf: .home, snow: .tops(1), note: "A clawfoot tub: it can climb right in", shape: pieces, ports: joints)
        case .chest: return D("Treasure Chest", .perch, 90, 60, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)
        case .coatRack: return D("Coat Rack", .perch, 44, 150, .rests, shelf: .home, snow: .tops(0.6), shape: pieces, ports: joints)
        case .beanbag: return D("Beanbag", .perch, 80, 48, .rests, shelf: .home, snow: .tops(1), shape: pieces, ports: joints)

        case .tv: return D("TV", .perch, 70, 64, .rests, shelf: .decor, snow: .tops(1), note: "An old television, flickering", shape: pieces, ports: joints)
        case .radio: return D("Radio", .perch, 60, 40, .rests, shelf: .decor, snow: .tops(1), shape: pieces, ports: joints)
        case .laptop: return D("Laptop", .perch, 64, 42, .rests, shelf: .decor, snow: .tops(0.6), shape: pieces, ports: joints)
        case .recordPlayer: return D("Record Player", .perch, 70, 30, .rests, shelf: .decor, snow: .tops(1), shape: pieces, ports: joints)
        case .globe: return D("Globe", .perch, 40, 58, .rests, shelf: .decor, snow: .tops(0.8), shape: pieces, ports: joints)
        case .vase: return D("Vase of Flowers", .perch, 32, 64, .rests, shelf: .decor, snow: .bare, shape: pieces, ports: joints)
        case .bookStack: return D("Books", .perch, 52, 40, .rests, shelf: .decor, snow: .tops(1), shape: pieces, ports: joints)
        case .flyJar: return D("Jar of Flies", .perch, 36, 48, .rests, shelf: .decor, snow: .tops(1), note: "A pantry, for later", shape: pieces, ports: joints)
        case .trophy: return D("Trophy", .perch, 34, 50, .rests, shelf: .decor, snow: .tops(0.6), shape: pieces, ports: joints)
        case .painting: return D("Painting", .scenery, 90, 64, .wedged, shelf: .decor, layer: .rear, mount: .wall, stretch: .both, snow: .bare,
                                 note: "A painting in a gilt frame — every one is different", shape: pieces, ports: joints)
        case .poster: return D("Poster", .scenery, 50, 68, .wedged, shelf: .decor, layer: .rear, mount: .wall, snow: .bare, shape: pieces, ports: joints)
        case .mirror: return D("Mirror", .scenery, 44, 70, .wedged, shelf: .decor, layer: .rear, mount: .wall, snow: .bare, shape: pieces, ports: joints)
        case .curtains: return D("Curtains", .scenery, 90, 110, .wedged, shelf: .decor, layer: .rear, mount: .wall, stretch: .both, snow: .bare,
                                 note: "A pair of curtains: hang them over a back window", shape: pieces, ports: joints)
        case .dartboard: return D("Dartboard", .scenery, 44, 44, .wedged, shelf: .decor, layer: .rear, mount: .wall, snow: .bare, shape: pieces, ports: joints)
        case .wallShelf: return D("Wall Shelf", .perch, 80, 20, .wedged, shelf: .decor, mount: .wall, stretch: .horizontal, snow: .tops(1),
                                  note: "A little shelf on the back wall, to put things on", shape: pieces, ports: joints)
        case .sconce: return D("Wall Lamp", .scenery, 24, 40, .wedged, shelf: .decor, layer: .rear, mount: .wall, snow: .bare, shape: pieces, ports: joints)
        case .chandelier: return D("Chandelier", .perch, 90, 140, .hangs, shelf: .decor, stretch: .vertical, sway: 0.008, windLean: 0.02,
                                   snow: .bare, note: "Candles on a hoop, hung from a ceiling, a beam or the lid", shape: pieces, ports: joints)
        case .stake: return D("Forked Stake", .perch, 30, 300, .rests, shelf: .supports, layer: .rear, stretch: .vertical, shadow: 0.6, snow: .tops(0.5),
                               note: "A straight stick with a fork at the top, stood behind a branch to hold it up", shape: pieces, ports: joints)

        // Structures.
        case .twistedBranch: return D("Twisted Branch", .perch, 260, 110, .wedged, shelf: .structures, snow: .tops(0.6),
                                      note: "Two limbs grown round and round each other", shape: pieces, ports: joints)
        case .threeFork: return D("Three-Pronged Fork", .perch, 190, 230, .rests, shelf: .structures, shadow: 0.4, snow: .tops(0.6),
                                  note: "An upright fork: lay a branch in its crotch", shape: pieces, ports: joints)
        case .exposedRoot: return D("Exposed Root", .perch, 240, 86, .ground, shelf: .structures, shadow: 0.9, snow: .tops(0.7),
                                    note: "A root arching up out of the soil, with room to creep under it", shape: pieces, ports: joints)
        case .rootTangle: return D("Root Tangle", .perch, 300, 120, .ground, shelf: .structures, shadow: 0.9, snow: .tops(0.7),
                                   note: "Roots looping in and out of the soil", shape: pieces, ports: joints)
        case .stump: return D("Tree Stump", .perch, 150, 120, .ground, shelf: .structures, snow: .tops(1),
                              note: "A sawn stump on its roots: things sit on its top", shape: pieces, ports: joints)
        case .driftwoodRoot: return D("Driftwood Root", .perch, 240, 170, .rests, shelf: .structures, shadow: 0.7, snow: .tops(0.6),
                                      note: "A bleached root ball, arms every way", shape: pieces, ports: joints)
        case .driftwoodBranch: return D("Driftwood Branch", .perch, 280, 140, .rests, shelf: .structures, shadow: 0.6, snow: .tops(0.7),
                                        note: "A bleached branch leaning up off the ground", shape: pieces, ports: joints)
        case .corkTunnel: return D("Cork Tunnel", .perch, 200, 86, .rests, shelf: .structures, snow: .tops(1),
                                   note: "A tube of cork on its side, open at both ends: it can go right through", shape: pieces, ports: joints)
        case .leaningBark: return D("Leaning Bark", .perch, 160, 190, .rests, shelf: .structures, shadow: 0.7, snow: .tops(0.8),
                                    note: "A sheet of bark stood at a lean, with a dry nook under it", shape: pieces, ports: joints)
        case .bambooTipi: return D("Bamboo Tripod", .perch, 160, 270, .rests, shelf: .structures, stretch: .vertical, shadow: 0.9, snow: .tops(0.5),
                                   note: "Three canes tied at the top: hang things from the tie, or lay a branch across", shape: pieces, ports: joints)
        case .hangingBranch: return D("Hanging Perch", .perch, 220, 200, .hangs, shelf: .structures, stretch: .vertical, sway: 0.02, windLean: 0.06,
                                      snow: .tops(0.5), note: "A branch slung on twine from the lid, a beam or a branch", shape: pieces, ports: joints)
        case .lianaLoop: return D("Liana Loop", .perch, 260, 230, .wedged, shelf: .structures, snow: .tops(0.5),
                                  note: "A woody vine with a loop in it: fasten each end to something", shape: pieces, ports: joints)
        case .hangingRoots: return D("Hanging Roots", .perch, 130, 260, .hangs, shelf: .structures, stretch: .vertical, sway: 0.03, windLean: 0.1,
                                     snow: .bare, note: "Air roots dangling from above, to climb down", shape: pieces, ports: joints)
        case .stickRaft: return D("Stick Raft", .perch, 180, 26, .wedged, shelf: .structures, stretch: .horizontal, snow: .tops(1),
                                  note: "A platform of sticks lashed side by side", shape: pieces, ports: joints)
        case .mossPlatform: return D("Mossy Ledge", .perch, 170, 40, .wedged, shelf: .structures, snow: .tops(1),
                                     note: "A shelf of bark with a cushion of moss on it", shape: pieces, ports: joints)
        case .rockSpire: return D("Rock Spire", .perch, 100, 280, .ground, shelf: .structures, stretch: .vertical, shadow: 1.1, snow: .tops(1),
                                  note: "Rock stacked up in ledges", shape: pieces, ports: joints)
        case .stoneArch: return D("Stone Arch", .perch, 280, 170, .ground, shelf: .structures, shadow: 0.9, snow: .tops(1),
                                  note: "An arch of rock to walk under, and over", shape: pieces, ports: joints)

        // Shelters.
        case .barkCave: return D("Bark Cave", .perch, 170, 110, .ground, shelf: .shelter, snow: .tops(1),
                                 note: "A curl of cork bark over a hollow, open on one side", shape: pieces, ports: joints)
        case .rockCrevice: return D("Rock Crevice", .perch, 220, 150, .ground, shelf: .shelter, snow: .tops(1),
                                    note: "A deep crack in the side of a rock, roofed over", shape: pieces, ports: joints)
        case .logDen: return D("Hollow Log Den", .perch, 220, 100, .ground, shelf: .shelter, snow: .tops(1),
                               note: "A log gone hollow and split along its side, open at one end", shape: pieces, ports: joints)
        case .curledLeafHide: return D("Curled-Leaf Hide", .perch, 175, 130, .rests, shelf: .shelter, snow: .tops(0.7),
                                       note: "A great dry leaf rolled into a scroll: in at the open side", shape: pieces, ports: joints)
        case .leafCanopy: return D("Leaf Canopy", .perch, 200, 150, .rests, shelf: .shelter, sway: 0.01, windLean: 0.04, shadow: 0.9, snow: .tops(0.6),
                                   note: "Huge leaves arching over the ground: shade, and out of the rain", shape: pieces, ports: joints)
        case .rootHollow: return D("Root Hollow", .perch, 200, 130, .ground, shelf: .shelter, snow: .tops(1),
                                   note: "A hollow under the roots of a stump", shape: pieces, ports: joints)
        case .mossyHide: return D("Mossy Hide", .perch, 160, 110, .ground, shelf: .shelter, snow: .tops(1),
                                  note: "A dome of mossy stone with a doorway in its side", shape: pieces, ports: joints)
        case .hangingLeafShelter: return D("Hanging Leaf Pouch", .perch, 110, 200, .hangs, shelf: .shelter, stretch: .vertical, sway: 0.02, windLean: 0.06,
                                           snow: .bare, note: "A leaf folded into a pouch, hanging on a thread", shape: pieces, ports: joints)
        case .overhang: return D("Rock Overhang", .perch, 240, 170, .ground, shelf: .shelter, snow: .tops(1),
                                 note: "Rock jutting out over a sheltered nook", shape: pieces, ports: joints)

        // Plants.
        case .smallFern: return D("Small Fern", .scenery, 70, 55, .rests, shelf: .plants, sway: 0.03, windLean: 0.1, shadow: 0.6, shape: pieces, ports: joints)
        case .largeFern: return D("Large Fern", .perch, 220, 170, .rests, shelf: .plants, sway: 0.012, windLean: 0.05, shadow: 0.6, snow: .tops(0.4),
                                  note: "Arching fronds it can walk out along", shape: pieces, ports: joints)
        case .broadLeaf: return D("Broad-Leaf Plant", .perch, 150, 140, .rests, shelf: .plants, sway: 0.012, windLean: 0.05, shadow: 0.6, snow: .tops(0.5),
                                  shape: pieces, ports: joints)
        case .trailingPlant: return D("Trailing Plant", .perch, 130, 170, .wedged, shelf: .plants, sway: 0.008, windLean: 0.05, shadow: 0, snow: .tops(0.4),
                                      note: "A pot of trailing stems: set it on a ledge or a branch and they hang down", shape: pieces, ports: joints)
        case .climbingVine: return D("Climbing Vine", .perch, 70, 260, .rests, shelf: .plants, stretch: .vertical, sway: 0.006, windLean: 0.03, shadow: 0.4,
                                     snow: .tops(0.3), note: "Grows up from the ground: stand it against something to climb", shape: pieces, ports: joints)
        case .grassClump: return D("Grass Clump", .perch, 110, 120, .rests, shelf: .plants, sway: 0.025, windLean: 0.12, shadow: 0.6, snow: .tops(0.3),
                                   note: "Stiff blades it can climb", shape: pieces, ports: joints)
        case .floweringPlant: return D("Flowering Plant", .perch, 90, 170, .rests, shelf: .plants, sway: 0.018, windLean: 0.07, shadow: 0.5, snow: .tops(0.4),
                                       note: "A tall flower with a head to sit on", shape: pieces, ports: joints)
        case .tinyFlowers: return D("Tiny Flowers", .scenery, 80, 22, .rests, shelf: .plants, sway: 0.02, windLean: 0.08, shadow: 0.5, shape: pieces, ports: joints)
        case .aloe: return D("Aloe", .perch, 90, 90, .rests, shelf: .plants, shadow: 0.7, snow: .tops(0.5), shape: pieces, ports: joints)
        case .jadePlant: return D("Jade Plant", .perch, 110, 120, .rests, shelf: .plants, shadow: 0.6, snow: .tops(0.6), note: "A little succulent tree", shape: pieces, ports: joints)
        case .lithops: return D("Living Stones", .scenery, 60, 24, .rests, shelf: .plants, note: "Succulents that look like pebbles", shape: pieces, ports: joints)
        case .airPlant: return D("Air Plant", .scenery, 50, 50, .wedged, shelf: .plants, note: "Needs no soil: set it on a branch or on bark", shape: pieces, ports: joints)
        case .miniPalm: return D("Parlour Palm", .perch, 120, 210, .rests, shelf: .plants, sway: 0.012, windLean: 0.05, shadow: 0.5, snow: .tops(0.4),
                                 shape: pieces, ports: joints)
        case .deadPlant: return D("Dry Plant", .perch, 100, 140, .rests, shelf: .plants, sway: 0.006, windLean: 0.04, shadow: 0.4, snow: .tops(0.4),
                                  note: "Dead stems gone papery", shape: pieces, ports: joints)
        case .fiddleheads: return D("Fiddleheads", .perch, 90, 110, .rests, shelf: .plants, sway: 0.012, windLean: 0.05, shadow: 0.5, snow: .tops(0.3),
                                    note: "Young fern fronds, still curled up", shape: pieces, ports: joints)
        case .creepingCover: return D("Ground Cover", .scenery, 140, 18, .rests, shelf: .plants, note: "A low carpet of little leaves", shape: pieces, ports: joints)
        case .hangingFoliage: return D("Hanging Foliage", .perch, 140, 240, .hangs, shelf: .plants, stretch: .vertical, sway: 0.03, windLean: 0.12,
                                       snow: .bare, note: "Leafy strands trailing down from above", shape: pieces, ports: joints)
        case .mossCushion: return D("Moss Cushion", .perch, 110, 34, .rests, shelf: .plants, snow: .tops(1), note: "A soft dome of moss", shape: pieces, ports: joints)

        // The ground.
        case .gravel: return D("Gravel", .scenery, 130, 10, .ground, shelf: .ground, shape: pieces, ports: joints)
        case .sandDrift: return D("Sand Drift", .perch, 180, 26, .ground, shelf: .ground, snow: .tops(1), note: "A low hump of rippled sand", shape: pieces, ports: joints)
        case .pineNeedles: return D("Pine Needles", .scenery, 140, 12, .rests, shelf: .ground, shape: pieces, ports: joints)

        // Natural details.
        case .mushroom: return D("Toadstool", .perch, 60, 80, .rests, shelf: .details, snow: .tops(0.6),
                                 note: "It can sit on the cap, or shelter under it", shape: pieces, ports: joints)
        case .mushroomCluster: return D("Mushroom Cluster", .perch, 110, 70, .rests, shelf: .details, snow: .tops(0.5), shape: pieces, ports: joints)
        case .tinyMushrooms: return D("Tiny Mushrooms", .scenery, 60, 22, .rests, shelf: .details, shape: pieces, ports: joints)
        case .glowMushrooms: return D("Glowing Mushrooms", .scenery, 70, 46, .rests, shelf: .details, note: "They glow in the dark", shape: pieces, ports: joints)
        case .shelfFungus: return D("Shelf Fungus", .perch, 60, 30, .wedged, shelf: .details, snow: .tops(1),
                                    note: "Brackets growing out of wood: little shelves to sit on", shape: pieces, ports: joints)
        case .lichen: return D("Lichen", .scenery, 50, 40, .wedged, shelf: .details, snow: .bare, note: "Grows on bark and stone", shape: pieces, ports: joints)
        case .acorn: return D("Acorn", .scenery, 26, 30, .rests, shelf: .details, shape: pieces, ports: joints)
        case .seedPod: return D("Seed Pod", .scenery, 56, 30, .rests, shelf: .details, note: "Split open, its seeds on silk", shape: pieces, ports: joints)
        case .pineCone: return D("Pine Cone", .perch, 46, 58, .rests, shelf: .details, snow: .tops(0.4), shape: pieces, ports: joints)
        case .seaShell: return D("Sea Shell", .perch, 74, 48, .rests, shelf: .details, snow: .tops(0.5), shape: pieces, ports: joints)
        case .snailShell: return D("Snail Shell", .perch, 48, 40, .rests, shelf: .details, snow: .tops(0.5), note: "Empty now", shape: pieces, ports: joints)
        case .fallenLeaf: return D("Fallen Leaf", .scenery, 76, 24, .rests, shelf: .details, shape: pieces, ports: joints)
        case .curledLeaf: return D("Curled Leaf", .scenery, 52, 30, .rests, shelf: .details, shape: pieces, ports: joints)
        case .deadLeaf: return D("Dead Leaf", .scenery, 56, 28, .rests, shelf: .details, shape: pieces, ports: joints)
        case .leafHeap: return D("Leaf Heap", .perch, 150, 50, .rests, shelf: .details, snow: .tops(1), note: "A drift of fallen leaves", shape: pieces, ports: joints)
        case .pebblePile: return D("Pebble Pile", .perch, 90, 38, .rests, shelf: .details, snow: .tops(1), shape: pieces, ports: joints)
        case .smoothStones: return D("Stacked Stones", .perch, 70, 74, .rests, shelf: .details, snow: .tops(1), note: "River stones, balanced", shape: pieces, ports: joints)
        case .crystalCluster: return D("Crystal Cluster", .perch, 120, 110, .rests, shelf: .details, snow: .tops(0.4), note: "Big crystals to climb", shape: pieces, ports: joints)
        case .petals: return D("Petals", .scenery, 70, 14, .rests, shelf: .details, shape: pieces, ports: joints)
        case .puddle: return D("Puddle", .scenery, 140, 14, .ground, shelf: .details, snow: .bare, shape: pieces, ports: joints)
        case .shedBark: return D("Shed Bark", .perch, 90, 34, .rests, shelf: .details, snow: .tops(0.6), note: "A strip of bark, curled as it dried", shape: pieces, ports: joints)
        case .twigPile: return D("Twig Pile", .perch, 120, 60, .rests, shelf: .details, snow: .tops(0.5), shape: pieces, ports: joints)

        // Functional.
        case .rockPool: return D("Rock Pool", .perch, 160, 42, .ground, shelf: .functional, snow: .bare,
                                 note: "A stone basin of water, to drink from", shape: pieces, ports: joints)
        case .feedingPlatform: return D("Feeding Ledge", .perch, 100, 120, .rests, shelf: .functional, shadow: 0.4, snow: .tops(1),
                                        note: "A tray on a stand, where food can be put", shape: pieces, ports: joints)
        case .baskingStone: return D("Basking Stone", .perch, 170, 56, .ground, shelf: .functional, snow: .tops(1),
                                     note: "A broad flat stone that keeps the warmth", shape: pieces, ports: joints)
        case .lookout: return D("Lookout", .perch, 80, 340, .rests, shelf: .functional, stretch: .vertical, shadow: 0.5, snow: .tops(0.8),
                                note: "A tall snag with a platform on top: the highest seat in the tank", shape: pieces, ports: joints)
        case .silkFrame: return D("Silk Frame", .perch, 170, 200, .rests, shelf: .functional, stretch: .both, shadow: 0.7, snow: .tops(0.5),
                                  note: "A frame of lashed twigs with room across it for silk", shape: pieces, ports: joints)
        case .climbingBark: return D("Climbing Bark", .perch, 110, 300, .rests, shelf: .functional, mount: .wall, stretch: .vertical, snow: .tops(0.8),
                                     note: "Rough bark fixed up the back wall, full of footholds", shape: pieces, ports: joints)
        case .moistMoss: return D("Damp Moss Bed", .perch, 150, 40, .rests, shelf: .functional, snow: .tops(1),
                                  note: "Deep wet moss in a saucer: a humid corner", shape: pieces, ports: joints)
        case .shelterCanopy: return D("Shelter Canopy", .perch, 170, 130, .rests, shelf: .functional, shadow: 0.9, snow: .tops(1),
                                      note: "A roof of bark on two forked sticks", shape: pieces, ports: joints)

        // Loose.
        case .looseLeaf: return D("Leaf", .scenery, 30, 14, .rests, shelf: .loose, shape: pieces, ports: joints)
        case .petal: return D("Petal", .scenery, 18, 10, .rests, shelf: .loose, shape: pieces, ports: joints)
        case .tinyTwig: return D("Tiny Twig", .scenery, 42, 10, .rests, shelf: .loose, shape: pieces, ports: joints)
        case .feather: return D("Feather", .scenery, 58, 16, .rests, shelf: .loose, shape: pieces, ports: joints)
        case .seed: return D("Winged Seed", .scenery, 32, 14, .rests, shelf: .loose, shape: pieces, ports: joints)
        case .smallShell: return D("Small Shell", .scenery, 24, 18, .rests, shelf: .loose, shape: pieces, ports: joints)
        case .tinyPebble: return D("Tiny Pebble", .scenery, 14, 10, .rests, shelf: .loose, shape: pieces, ports: joints)
        }
    }

    var label: String { definition.label }

    /// Climbable, or just to look at.
    var climbable: Bool { definition.category == .perch }

    /// Size in world points (the same as the screen's).
    var defaultSize: CGSize { definition.size }

    /// Hangs from the lid rather than standing on the ground.
    var hangs: Bool { definition.placement == .hangs }

    /// May be put up off the ground: what is propped on or rests on other
    /// things. Rocks and pots and the like stand on the ground.
    var liftable: Bool { definition.placement == .rests || definition.placement == .wedged }

    /// Moves on its own — sways in the air of the tank.
    var sways: Bool { definition.sway > 0 }

    /// Where it goes by default: low things and foliage can go in front of
    /// the spider; furniture it climbs, and the hardware at the back, are
    /// always behind it.
    var canGoInFront: Bool { !climbable && definition.layer != .rear }

    /// Hardware at the back, behind the furniture.
    var atBack: Bool { definition.layer == .rear }

    /// Fastens to other things (has ports).
    var fastens: Bool { !definition.ports(CGRect(origin: .zero, size: defaultSize), 1, 1).isEmpty }
}

/// A kind of thing in the tank: everything about it but its picture.
struct HabitatObjectDefinition {
    /// Which part of the picker it goes in.
    enum Category {
        /// Furniture: it has parts the spider can climb.
        case perch
        /// To look at: plants and details it walks past or through.
        case scenery
    }

    /// Where it may be put.
    enum Placement {
        /// On the ground, always.
        case ground
        /// Anywhere; let go of up in the air, it comes to rest on whatever
        /// is under it.
        case rests
        /// Anywhere, and it stays where it is put (a branch, wedged).
        case wedged
        /// From the lid.
        case hangs
    }

    /// Which part of the Add page it is in.
    enum Shelf: String, CaseIterable {
        case structures, supports, shelter, plants, ground, details, functional, loose, built, building, walls, home, decor

        var label: String {
            switch self {
            case .structures: return "Structures"
            case .supports: return "Supports"
            case .shelter: return "Shelter"
            case .plants: return "Plants"
            case .ground: return "Ground"
            case .details: return "Details"
            case .functional: return "Functional"
            case .loose: return "Loose"
            case .built: return "Built"
            case .building: return "Building"
            case .walls: return "Backing"
            case .home: return "Home"
            case .decor: return "Decor"
            }
        }

        /// Its heading on the Add page.
        var heading: String {
            switch self {
            case .structures: return "Structures — branches, roots, bark, rock"
            case .supports: return "Supports — fixed to the back wall"
            case .shelter: return "Shelter — covered places to get into"
            case .plants: return "Plants"
            case .ground: return "Ground"
            case .details: return "Natural details"
            case .functional: return "Functional — water, food, warmth, a view"
            case .loose: return "Loose objects — light enough to blow about"
            case .built: return "Built — timber, board and brick"
            case .building: return "Building — floors, walls, doors, a roof"
            case .walls: return "Backing — the back walls of rooms"
            case .home: return "Home — furniture"
            case .decor: return "Decor — little things, and for the walls"
            }
        }

        /// The natural world, as against what is made by hand.
        var natural: Bool { ![.supports, .built, .building, .walls, .home, .decor].contains(self) }
    }

    /// A part of a shelf, under a heading of its own.
    enum Group: String, CaseIterable {
        case branches, roots, driftwood, bark, bamboo, vines, platforms, rocks
        case ferns, leafy, flowering, succulents, climbers, grasses
        case fungi, seeds, leaves, stones, shells, water

        var label: String {
            switch self {
            case .branches: return "Branches"
            case .roots: return "Roots & stumps"
            case .driftwood: return "Driftwood"
            case .bark: return "Bark & logs"
            case .bamboo: return "Bamboo & stems"
            case .vines: return "Vines & hanging"
            case .platforms: return "Platforms & ledges"
            case .rocks: return "Rock"
            case .ferns: return "Ferns"
            case .leafy: return "Leafy"
            case .flowering: return "Flowers"
            case .succulents: return "Succulents & dry"
            case .climbers: return "Climbing & trailing"
            case .grasses: return "Grass, moss & cover"
            case .fungi: return "Fungi"
            case .seeds: return "Seeds & cones"
            case .leaves: return "Leaves & bark"
            case .stones: return "Stones & crystals"
            case .shells: return "Shells"
            case .water: return "Water"
            }
        }
    }

    /// Which layer it is drawn in.
    enum Layer {
        /// With the rest of the furniture, behind the spider.
        case normal
        /// Behind all the furniture: hardware fixed to the back wall.
        case rear
    }

    /// Fixed to something that isn't in the tank's list of things.
    enum Mount {
        case none
        /// The back wall (or the glass at the back): held up wherever it is.
        case wall
    }

    /// Pulled out by a corner, it gets longer this way (and no thicker) —
    /// or, a wall behind things, any shape.
    enum Stretch { case vertical, horizontal, both }

    /// How snow lies on it.
    enum Snow {
        /// Along the tops of its solid parts, this deep (for the depth).
        case tops(CGFloat)
        /// A sprinkle over it.
        case sprinkle
        /// None settles on it.
        case bare
    }

    var label: String
    var category: Category
    var shelf: Shelf
    /// Its heading within its shelf, if the shelf has more than one.
    var group: Group?
    /// What it is, where it belongs and what it is for (see `HabitatTraits`).
    var traits = HabitatTraits()
    var layer: Layer
    var mount: Mount
    var stretch: Stretch?
    /// The size it comes in, in world points.
    var size: CGSize
    var placement: Placement
    /// How far it sways to and fro on its own, as a shear (0: it doesn't).
    var sway: CGFloat
    /// How far it leans over in a gale, as a shear.
    var windLean: CGFloat
    /// How wide its shadow on the ground is, for its width.
    var shadow: CGFloat
    var snow: Snow
    /// What it is, for a tooltip (if its name doesn't say).
    var note: String?
    /// Its physical shape, in the world, for a thing standing in `rect`
    /// (unflipped): see `ObjectGeometry`.
    var shape: (_ rect: CGRect, _ seed: Int, _ u: CGFloat) -> ObjectGeometry
    /// Where other things fasten to it, likewise (see HabitatStructures.swift).
    var ports: (_ rect: CGRect, _ seed: Int, _ u: CGFloat) -> [HabitatPort]

    init(_ label: String, _ category: Category, _ w: CGFloat, _ h: CGFloat, _ placement: Placement,
         shelf: Shelf? = nil, layer: Layer = .normal, mount: Mount = .none, stretch: Stretch? = nil,
         sway: CGFloat = 0, windLean: CGFloat = 0, shadow: CGFloat = 0.96, snow: Snow? = nil, note: String? = nil,
         shape: @escaping (CGRect, Int, CGFloat) -> ObjectGeometry,
         ports: @escaping (CGRect, Int, CGFloat) -> [HabitatPort] = { _, _, _ in [] }) {
        self.label = label
        self.category = category
        self.shelf = shelf ?? (category == .perch ? .structures : .plants)
        self.layer = layer
        self.mount = mount
        self.stretch = stretch
        size = CGSize(width: w, height: h)
        self.placement = placement
        self.sway = sway
        self.windLean = windLean
        self.shadow = shadow
        self.snow = snow ?? (category == .perch ? .tops(0.8) : .sprinkle)
        self.note = note
        self.shape = shape
        self.ports = ports
    }
}

// MARK: - What it is, where it belongs, what it is for
//
// Nothing in the spider reads these yet: they are what later behaviour
// (drinking, basking, hiding, curiosity about things, lightweight physics
// for what blows about) will go by — and, now, what the layouts and the
// Add page go by: what suits which scenery, and where on what it grows.

/// What a thing is made of.
enum HabitatMaterial: String, CaseIterable {
    case wood, bark, root, driftwood, bamboo, stem, leaf, moss, fungus, stone, crystal, sand, soil, water, shell, seed, feather
    /// By hand: timber, metal, cloth, pottery.
    case made
}

/// What a thing is for, to the spider.
enum HabitatFunction: String, CaseIterable {
    /// Water to drink.
    case water
    /// Where food is put.
    case feeding
    /// A warm place to sit in the light.
    case basking
    /// Somewhere high to watch from.
    case lookout
    /// Room and fixings for silk.
    case silk
    /// A face to climb.
    case climbing
    /// Damp: for moulting, and a drink of dew.
    case humid
    /// A roof: out of the rain and the sun.
    case cover
    /// Somewhere enclosed to withdraw into.
    case retreat

    var label: String {
        switch self {
        case .water: return "water"
        case .feeding: return "feeding"
        case .basking: return "basking"
        case .lookout: return "lookout"
        case .silk: return "silk"
        case .climbing: return "climbing"
        case .humid: return "humid"
        case .cover: return "cover"
        case .retreat: return "hide"
        }
    }
}

/// Where a thing is found: what it grows on or lies on.
struct HabitatNiche {
    /// The materials of what is under it (soil: the tank's own floor).
    /// Empty: anywhere.
    var on: Set<HabitatMaterial> = []
    /// Out of the side of it (a bracket fungus on a trunk), not on its top.
    var side = false
    /// By water.
    var damp = false
}

/// How something small and loose would move, for a light physics to come:
/// blown by the wind, nudged by the spider, tumbling off a ledge.
struct LooseBody {
    enum Motion {
        /// Rocks and drifts down like a leaf.
        case flutter
        /// Spins as it falls, like a winged seed.
        case spin
        /// Rolls: round things.
        case roll
        /// Tumbles end over end.
        case tumble
        /// Slides and stops.
        case slide
    }
    var motion: Motion
    /// Grams, more or less: how hard it is to shift.
    var mass: CGFloat
    /// How much the air holds it back (0: a stone … 1: a feather).
    var drag: CGFloat
    /// How readily a breeze moves it (0…1).
    var windCatch: CGFloat
    var bounce: CGFloat
    var friction: CGFloat
    /// Light enough for the spider to push along.
    var pushable: Bool { mass < 3 }
}

/// A kind of thing's nature (its definition's `traits`).
struct HabitatTraits {
    var material: HabitatMaterial = .made
    /// The sceneries it belongs in (empty: any).
    var suits: Set<Biome> = []
    var niche = HabitatNiche()
    var functions: Set<HabitatFunction> = []
    /// Small and light enough to move about (nil: it stays put).
    var loose: LooseBody?
    /// Other words for it, for searching.
    var aka = ""
}

extension HabitatItemKind {
    /// Its heading within its shelf.
    fileprivate var group: HabitatObjectDefinition.Group? {
        switch self {
        case .branch, .thinBranch, .mediumBranch, .thickBranch, .shortBranch, .longBranch, .forkedBranch, .yBranch, .crookedBranch, .twig,
             .twistedBranch, .threeFork:
            return .branches
        case .root, .climbingRoot, .exposedRoot, .rootTangle, .stump: return .roots
        case .driftwood, .driftwoodArch, .driftwoodSnag, .driftwoodRoot, .driftwoodBranch: return .driftwood
        case .log, .hide, .corkBark, .corkTube, .corkTunnel, .leaningBark: return .bark
        case .bamboo, .bambooPole, .bambooSegment, .bambooTipi, .driedStem: return .bamboo
        case .vine, .thickVine, .thinVine, .hangingBranch, .lianaLoop, .hangingRoots: return .vines
        case .corkSlab, .barkLedge, .slateLedge, .stickRaft, .mossPlatform: return .platforms
        case .rock, .boulder, .rockSpire, .stoneArch: return .rocks
        case .fern, .smallFern, .largeFern, .fiddleheads: return .ferns
        case .plant, .broadLeaf, .miniPalm: return .leafy
        case .flower, .floweringPlant, .tinyFlowers: return .flowering
        case .cactus, .succulent, .aloe, .jadePlant, .lithops, .airPlant, .deadPlant: return .succulents
        case .climbingVine, .trailingPlant, .hangingFoliage: return .climbers
        case .grass, .grassClump, .mossCushion, .creepingCover: return .grasses
        case .mushrooms, .mushroom, .mushroomCluster, .tinyMushrooms, .glowMushrooms, .shelfFungus, .lichen: return .fungi
        case .acorn, .seedPod, .pineCone: return .seeds
        case .fallenLeaf, .curledLeaf, .deadLeaf, .leafHeap, .petals, .shedBark, .twigPile: return .leaves
        case .crystal, .crystalCluster, .pebblePile, .smoothStones: return .stones
        case .seaShell, .snailShell: return .shells
        case .puddle: return .water
        default: return nil
        }
    }

    /// Its nature: see `HabitatTraits`.
    fileprivate var traits: HabitatTraits {
        typealias M = HabitatMaterial
        let branchy: Set<Biome> = [.forest, .jungle, .meadow, .night, .tundra]
        let woods: Set<Biome> = [.forest, .jungle, .night, .tundra]
        let green: Set<Biome> = [.forest, .jungle, .meadow, .night]
        let shady: Set<Biome> = [.forest, .jungle, .night]
        let dry: Set<Biome> = [.desert, .beach]
        let stony: Set<Biome> = [.desert, .cave, .beach, .tundra]
        func T(_ m: M, _ suits: Set<Biome> = [], on: Set<M> = [], side: Bool = false, damp: Bool = false,
               _ fn: Set<HabitatFunction> = [], loose: LooseBody? = nil, aka: String = "") -> HabitatTraits {
            HabitatTraits(material: m, suits: suits, niche: HabitatNiche(on: on, side: side, damp: damp), functions: fn, loose: loose, aka: aka)
        }
        func L(_ m: LooseBody.Motion, _ mass: CGFloat, _ drag: CGFloat, _ wind: CGFloat, _ bounce: CGFloat, _ friction: CGFloat) -> LooseBody {
            LooseBody(motion: m, mass: mass, drag: drag, windCatch: wind, bounce: bounce, friction: friction)
        }
        switch self {
        // What was there before.
        case .log: return T(.wood, woods.union([.meadow]))
        case .hide: return T(.wood, woods.union([.meadow]), aka: "hollow")
        case .branch, .thinBranch, .mediumBranch, .thickBranch, .shortBranch, .longBranch, .forkedBranch, .yBranch, .crookedBranch, .twig:
            return T(.wood, branchy)
        case .driftwood, .driftwoodArch, .driftwoodSnag: return T(.driftwood, dry)
        case .corkBark, .corkTube, .corkSlab, .barkLedge: return T(.bark, woods.union([.meadow]))
        case .rock, .boulder: return T(.stone, aka: "stone")
        case .slateLedge: return T(.stone)
        case .bamboo, .bambooPole, .bambooSegment: return T(.bamboo, [.jungle])
        case .cactus: return T(.stem, [.desert])
        case .plant: return T(.leaf, green)
        case .vine, .thickVine, .thinVine: return T(.stem, [.jungle, .forest, .night, .cave])
        case .waterDish: return T(.stone, [], [.water], aka: "drink")
        case .fern: return T(.leaf, shady)
        case .grass: return T(.leaf, [.forest, .jungle, .meadow, .night, .beach, .desert, .tundra])
        case .flower: return T(.leaf, [.meadow, .forest, .jungle])
        case .succulent: return T(.stem, dry)
        case .mushrooms: return T(.fungus, [.forest, .jungle, .night, .cave], on: [.wood, .bark, .soil, .moss], damp: true, aka: "toadstool")
        case .moss: return T(.moss, [.forest, .jungle, .night, .tundra, .cave], damp: true)
        case .leafPile: return T(.leaf, [.forest, .night, .meadow, .tundra], aka: "litter")
        case .pebbles: return T(.stone)
        case .twigs: return T(.wood, branchy.union([.beach]))
        case .crystal: return T(.crystal, [.cave, .night], aka: "gem")
        case .root, .climbingRoot: return T(.root, woods)
        case .driedStem: return T(.stem, [.desert, .meadow, .tundra, .beach])
        case .stake: return T(.wood)

        // Structures.
        case .twistedBranch, .threeFork: return T(.wood, branchy)
        case .exposedRoot, .rootTangle: return T(.root, woods.union([.meadow]), [.cover])
        case .stump: return T(.wood, woods.union([.meadow]), aka: "tree")
        case .driftwoodRoot, .driftwoodBranch: return T(.driftwood, dry)
        case .corkTunnel: return T(.bark, woods.union([.meadow]), [.cover, .retreat], aka: "tube hide")
        case .leaningBark: return T(.bark, woods.union([.meadow]), [.cover])
        case .bambooTipi: return T(.bamboo, [.jungle], aka: "cane")
        case .hangingBranch: return T(.wood, branchy, aka: "swing")
        case .lianaLoop: return T(.stem, [.jungle, .forest, .night], aka: "vine")
        case .hangingRoots: return T(.root, [.jungle, .forest, .night, .cave])
        case .stickRaft: return T(.wood, [], aka: "platform")
        case .mossPlatform: return T(.bark, green.union([.tundra]), aka: "platform shelf")
        case .rockSpire: return T(.stone, stony, aka: "pillar")
        case .stoneArch: return T(.stone, stony.union([.meadow]), [.cover])

        // Shelters.
        case .barkCave: return T(.bark, woods.union([.meadow]), [.cover, .retreat], aka: "hide den")
        case .rockCrevice: return T(.stone, stony.union([.forest, .meadow]), [.cover, .retreat], aka: "hide crack")
        case .logDen: return T(.wood, woods.union([.meadow]), [.cover, .retreat], aka: "hide hollow log")
        case .curledLeafHide: return T(.leaf, green, [.cover, .retreat], aka: "hide")
        case .leafCanopy: return T(.leaf, shady, [.cover], aka: "shade umbrella")
        case .rootHollow: return T(.root, woods, [.cover, .retreat], aka: "hide den")
        case .mossyHide: return T(.stone, [.forest, .jungle, .night, .cave, .tundra], [.cover, .retreat], aka: "hide dome")
        case .hangingLeafShelter: return T(.leaf, shady, [.cover, .retreat], aka: "hide")
        case .overhang: return T(.stone, stony.union([.forest]), [.cover], aka: "ledge cave")

        // Plants.
        case .smallFern, .largeFern, .fiddleheads: return T(.leaf, shady.union([.cave]))
        case .broadLeaf: return T(.leaf, shady)
        case .trailingPlant: return T(.leaf, green, aka: "pothos ivy")
        case .climbingVine: return T(.stem, green, aka: "ivy")
        case .grassClump: return T(.leaf, [.meadow, .forest, .beach, .tundra, .night])
        case .floweringPlant: return T(.leaf, [.meadow, .forest, .jungle], aka: "daisy sunflower")
        case .tinyFlowers: return T(.leaf, [.meadow, .forest, .night])
        case .aloe, .jadePlant: return T(.leaf, dry, aka: "succulent")
        case .lithops: return T(.leaf, [.desert], aka: "succulent")
        case .airPlant: return T(.leaf, [.jungle, .desert, .forest], on: [.wood, .bark, .driftwood, .stone], aka: "tillandsia")
        case .miniPalm: return T(.leaf, [.jungle, .beach])
        case .deadPlant: return T(.stem, [.desert, .tundra, .beach, .meadow], aka: "dead")
        case .creepingCover: return T(.leaf, [.meadow, .forest, .night], aka: "clover")
        case .hangingFoliage: return T(.leaf, [.jungle, .forest, .night, .cave], aka: "ivy")
        case .mossCushion: return T(.moss, [.forest, .jungle, .night, .tundra, .cave], damp: true)

        // The ground.
        case .gravel: return T(.stone, stony, aka: "grit")
        case .sandDrift: return T(.sand, dry, aka: "dune")
        case .pineNeedles: return T(.leaf, [.forest, .tundra, .night])

        // Natural details.
        case .mushroom: return T(.fungus, [.forest, .jungle, .night, .meadow], on: [.wood, .bark, .soil, .moss], damp: true, [.cover], aka: "toadstool")
        case .mushroomCluster: return T(.fungus, shady, on: [.wood, .bark, .root, .soil])
        case .tinyMushrooms: return T(.fungus, shady.union([.cave]), on: [.wood, .bark, .moss, .soil])
        case .glowMushrooms: return T(.fungus, [.cave, .night, .jungle], on: [.wood, .soil, .moss, .stone], aka: "light")
        case .shelfFungus: return T(.fungus, shady, on: [.wood, .bark, .root], side: true, aka: "bracket")
        case .lichen: return T(.fungus, [.forest, .tundra, .night, .meadow, .cave], on: [.wood, .bark, .stone, .root], side: true)
        case .acorn: return T(.seed, [.forest, .meadow, .night], loose: L(.roll, 3.5, 0.08, 0.05, 0.3, 0.35), aka: "nut")
        case .seedPod: return T(.seed, [.meadow, .forest, .desert], aka: "milkweed")
        case .pineCone: return T(.seed, [.forest, .tundra, .night], loose: L(.roll, 8, 0.12, 0.04, 0.25, 0.5))
        case .seaShell: return T(.shell, [.beach], aka: "conch")
        case .snailShell: return T(.shell, green)
        case .fallenLeaf: return T(.leaf, green, loose: L(.flutter, 0.6, 0.8, 0.7, 0.05, 0.6))
        case .curledLeaf: return T(.leaf, [.forest, .meadow, .night, .tundra], loose: L(.tumble, 0.3, 0.6, 0.8, 0.1, 0.5))
        case .deadLeaf: return T(.leaf, [.forest, .tundra, .night, .meadow, .desert], loose: L(.flutter, 0.3, 0.8, 0.85, 0.05, 0.55))
        case .leafHeap: return T(.leaf, [.forest, .night, .meadow, .tundra], aka: "litter")
        case .pebblePile: return T(.stone, aka: "cairn")
        case .smoothStones: return T(.stone, [.beach, .forest, .cave, .tundra, .meadow], aka: "cairn river")
        case .crystalCluster: return T(.crystal, [.cave, .night], aka: "gem geode")
        case .petals: return T(.leaf, [.meadow, .forest, .jungle])
        case .puddle: return T(.water, [.forest, .jungle, .meadow, .night, .tundra, .cave], damp: true, [.water], aka: "drink")
        case .shedBark: return T(.bark, woods)
        case .twigPile: return T(.wood, branchy.union([.beach]))

        // Functional.
        case .rockPool: return T(.stone, [], damp: true, [.water], aka: "drink")
        case .feedingPlatform: return T(.bark, [], [.feeding], aka: "food")
        case .baskingStone: return T(.stone, [], [.basking], aka: "warm sun")
        case .lookout: return T(.driftwood, [], [.lookout], aka: "high")
        case .silkFrame: return T(.wood, [], [.silk], aka: "web")
        case .climbingBark: return T(.bark, [], [.climbing], aka: "wall")
        case .moistMoss: return T(.moss, [], damp: true, [.humid], aka: "wet damp")
        case .shelterCanopy: return T(.bark, [], [.cover], aka: "roof")

        // Loose.
        case .looseLeaf: return T(.leaf, green.union([.tundra]), loose: L(.flutter, 0.2, 0.85, 0.8, 0.05, 0.6))
        case .petal: return T(.leaf, [.meadow, .forest, .jungle], loose: L(.flutter, 0.05, 0.9, 0.95, 0.02, 0.5))
        case .tinyTwig: return T(.wood, branchy, loose: L(.tumble, 0.4, 0.3, 0.3, 0.2, 0.7), aka: "stick")
        case .feather: return T(.feather, [], loose: L(.flutter, 0.1, 0.95, 1, 0.02, 0.4))
        case .seed: return T(.seed, [.forest, .meadow, .night], loose: L(.spin, 0.15, 0.8, 0.7, 0.1, 0.5), aka: "samara maple")
        case .smallShell: return T(.shell, [.beach], loose: L(.slide, 1.2, 0.1, 0.1, 0.35, 0.5))
        case .tinyPebble: return T(.stone, [], loose: L(.roll, 2, 0.05, 0.02, 0.3, 0.3), aka: "stone")

        default: return T(.made)
        }
    }
}

extension HabitatItemKind {
    /// What it is for, if anything.
    var functions: Set<HabitatFunction> { definition.traits.functions }

    /// How it would move, if it is loose.
    var loose: LooseBody? { definition.traits.loose }

    /// Whether it belongs in this scenery.
    func suits(_ b: Biome) -> Bool { definition.traits.suits.isEmpty || definition.traits.suits.contains(b) }

    /// Whether a search matches it: its name, what it is, what it is for.
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        let d = definition
        let words = [d.label, d.note ?? "", d.shelf.label, d.group?.label ?? "", d.traits.material == .made ? "" : d.traits.material.rawValue,
                     d.traits.functions.map(\.label).joined(separator: " "), d.traits.aka, d.traits.loose == nil ? "" : "loose"]
            .joined(separator: " ").lowercased()
        return q.split(separator: " ").allSatisfy { words.contains($0) }
    }
}

// MARK: - A thing in the tank

struct HabitatItem: Codable, Equatable, Identifiable {
    /// Its number in this habitat: what the tank's editing, its layers and
    /// its surfaces know it by. Never reused within a habitat.
    var id: Int
    /// Who it is, for good: made once, when it is first put in a tank, and
    /// kept through saving, loading, moving and resizing. What anything that
    /// remembers a particular thing — this log, that stone — holds on to.
    var uid: String
    var kind: HabitatItemKind
    /// Centre across, in world points. Standing things: `y` is how far above
    /// the ground its base is (0 on the ground). Hanging things: `y` is its
    /// top (the lid is the top of the world).
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat
    var flipped = false
    var seed = 0
    /// Drawn in front of the spider (foreground foliage), or behind it.
    var front = false

    init(id: Int, uid: String = HabitatItem.newUID(), kind: HabitatItemKind, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
         flipped: Bool = false, seed: Int = 0, front: Bool = false) {
        self.id = id
        self.uid = uid
        self.kind = kind
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.flipped = flipped
        self.seed = seed
        self.front = front
    }

    static func newUID() -> String { UUID().uuidString }

    // A habitat saved before things had a `uid` has none: it is given one
    // as it loads (see `Habitat.load`), and kept from then on.
    private enum CodingKeys: String, CodingKey { case id, uid, kind, x, y, w, h, flipped, seed, front }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        uid = try c.decodeIfPresent(String.self, forKey: .uid) ?? ""
        kind = try c.decode(HabitatItemKind.self, forKey: .kind)
        x = try c.decode(CGFloat.self, forKey: .x)
        y = try c.decode(CGFloat.self, forKey: .y)
        w = try c.decode(CGFloat.self, forKey: .w)
        h = try c.decode(CGFloat.self, forKey: .h)
        flipped = try c.decodeIfPresent(Bool.self, forKey: .flipped) ?? false
        seed = try c.decodeIfPresent(Int.self, forKey: .seed) ?? 0
        front = try c.decodeIfPresent(Bool.self, forKey: .front) ?? false
    }

    /// Its rectangle in the world.
    var rect: CGRect {
        kind.hangs ? CGRect(x: x - w / 2, y: y - h, width: w, height: h)
                   : CGRect(x: x - w / 2, y: HabitatLayout.ground + y, width: w, height: h)
    }

    var onGround: Bool { !kind.hangs && y < 2 }
    var inFront: Bool { front && kind.canGoInFront }

    /// How much bigger or smaller than it comes it is drawn: the unit its
    /// picture's strokes, and the thickness of its parts, go by.
    var unit: CGFloat { HabitatShape.unit(kind, rect) }
}
