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

    var definition: HabitatObjectDefinition {
        typealias D = HabitatObjectDefinition
        let pieces = HabitatShape.pieceShape(self), joints = HabitatShape.piecePorts(self)
        switch self {
        case .log: return D("Log", .perch, 180, 50, .rests, shelf: .bark, shape: HabitatShape.log)
        case .branch: return D("Branch", .perch, 230, 130, .wedged, shelf: .structures, shape: HabitatShape.branch, ports: joints)
        case .driftwood: return D("Driftwood", .perch, 200, 56, .rests, shelf: .structures, shape: HabitatShape.driftwood)
        case .corkBark: return D("Cork Bark", .perch, 74, 210, .ground, shelf: .bark, shadow: 0.8, shape: HabitatShape.corkBark)
        case .hide: return D("Hollow Log", .perch, 130, 66, .ground, shelf: .bark, shape: HabitatShape.hollowLog)
        case .rock: return D("Rock", .perch, 76, 44, .ground, shelf: .furniture, shape: HabitatShape.rock)
        case .boulder: return D("Boulder", .perch, 140, 92, .ground, shelf: .furniture, shape: HabitatShape.rock)
        case .bamboo: return D("Bamboo", .perch, 60, 250, .ground, shelf: .structures, sway: 0.012, windLean: 0.035, shadow: 0.8, shape: HabitatShape.bamboo)
        case .cactus: return D("Cactus", .perch, 70, 150, .ground, shelf: .furniture, shadow: 0.8, shape: HabitatShape.cactus)
        case .plant: return D("Leafy Plant", .perch, 120, 150, .rests, shelf: .furniture, sway: 0.018, windLean: 0.05, shadow: 0.5, shape: HabitatShape.plant)
        case .vine: return D("Hanging Vine", .perch, 40, 230, .hangs, shelf: .vines, stretch: .vertical, sway: 0.05, windLean: 0.14,
                             snow: .bare, shape: HabitatShape.vine, ports: joints)
        case .waterDish: return D("Water Dish", .perch, 96, 26, .ground, shelf: .furniture, snow: .bare, shape: HabitatShape.waterDish)
        case .fern: return D("Fern", .scenery, 130, 90, .rests, sway: 0.035, windLean: 0.1, shadow: 0.6, shape: HabitatShape.fern)
        case .grass: return D("Tall Grass", .scenery, 90, 84, .rests, sway: 0.035, windLean: 0.16, shadow: 0.6, shape: HabitatShape.grass)
        case .flower: return D("Flowers", .scenery, 80, 80, .rests, sway: 0.035, windLean: 0.13, shadow: 0.6, shape: HabitatShape.flowers)
        case .succulent: return D("Succulent", .scenery, 64, 46, .rests, shape: HabitatShape.succulent)
        case .mushrooms: return D("Mushrooms", .scenery, 66, 46, .rests, shape: HabitatShape.mushrooms)
        case .moss: return D("Moss", .scenery, 120, 24, .rests, shape: HabitatShape.groundCover)
        case .leafPile: return D("Leaf Litter", .scenery, 130, 26, .rests, shape: HabitatShape.groundCover)
        case .pebbles: return D("Pebbles", .scenery, 90, 20, .rests, shape: HabitatShape.groundCover)
        case .twigs: return D("Twigs", .scenery, 96, 30, .rests, shape: HabitatShape.groundCover)
        case .crystal: return D("Crystals", .scenery, 64, 70, .rests, shape: HabitatShape.crystals)

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

        case .corkSlab: return D("Cork Slab", .perch, 190, 46, .wedged, shelf: .platforms, snow: .tops(1), shape: pieces, ports: joints)
        case .corkTube: return D("Cork Tube", .perch, 90, 200, .rests, shelf: .bark, stretch: .vertical, shadow: 0.9, snow: .tops(0.8), shape: pieces, ports: joints)
        case .barkLedge: return D("Bark Ledge", .perch, 170, 30, .wedged, shelf: .platforms, snow: .tops(1), shape: pieces, ports: joints)
        case .slateLedge: return D("Slate Shelf", .perch, 160, 24, .wedged, shelf: .platforms, snow: .tops(1), shape: pieces, ports: joints)

        case .thickVine: return D("Thick Vine", .perch, 260, 90, .wedged, shelf: .vines, stretch: .horizontal, snow: .tops(0.5), shape: pieces, ports: joints)
        case .thinVine: return D("Thin Vine", .perch, 36, 170, .hangs, shelf: .vines, stretch: .vertical, sway: 0.05, windLean: 0.16,
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
        case structures, supports, vines, bark, platforms, built, building, walls, home, decor, furniture, plants

        var label: String {
            switch self {
            case .structures: return "Structures"
            case .built: return "Built"
            case .building: return "Building"
            case .walls: return "Backing"
            case .home: return "Home"
            case .decor: return "Decor"
            case .supports: return "Supports"
            case .vines: return "Vines"
            case .bark: return "Bark"
            case .platforms: return "Platforms"
            case .furniture: return "Stones & More"
            case .plants: return "Plants"
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
        self.shelf = shelf ?? (category == .perch ? .furniture : .plants)
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
