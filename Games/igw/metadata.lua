--[[
    IGW v2 — Game Metadata

    Flat table keyed by node class name. Combines what was previously split
    across init.cfg (preload/mode/wiring/config), definitions.lua (cascade),
    and inline overrides into a single authoritative file.

    Resolution: metadata.defaults → metadata[NodeName] → ClassResolver (future themes)
--]]

return {
    -- Pipeline node load order (orchestrator is implicit from init.cfg)
    nodes = {
        "WorldBridge",
        "DungeonOrchestrator",
        "InventoryNode", "SplinePlannerNode", "BlockoutNode",
        "TerrainPainterNode", "MeshTerrainPainterNode", "RockScatterNode",
        "MountainRoomPlacer", "ShellBuilder", "DoorPlanner",
        "TrussBuilder", "LightBuilder", "Materializer",
        "IceTerrainPainter", "DoorCutter",
        "DependencyResolver",
        "PassageNode",
        "ItemNode",
        "BackpackToolbar",
        "MiniMap",
    },

    ---------------------------------------------------------------------------
    -- Orchestrator — WorldMapOrchestrator owns biomes + world map
    ---------------------------------------------------------------------------

    WorldMapOrchestrator = {
        startBiome = "mountain",
        portalCountdownSeconds = 5,
        miniMapCsgRadius = 3,  -- chunks (Chebyshev distance from player)

        worldMap = {
            mountain = { elevation = 4, connects = {} },  -- blockout testing
            desert  = { elevation = 1,  connects = { "meadow", "sewer" } },
            meadow  = { elevation = 2,  connects = { "desert", "ice", "village" } },
            ice     = { elevation = 3,  connects = { "meadow", "crystal" } },
            village = { elevation = 2,  connects = { "meadow" } },
            sewer   = { elevation = -1, connects = { "desert", "crystal" } },
            crystal = { elevation = -2, connects = { "sewer", "ice", "lava" } },
            lava    = { elevation = -3, connects = { "crystal" } },
        },

        biomes = {
            lava = {
                paletteClass = "palette-classic-lava",
                terrainWall = "Rock",
                terrainFloor = "CrackedLava",
                partWall = "Cobblestone",
                partFloor = "CrackedLava",
                lightType = "PointLight",
                lightStyle = "cave-point-light",
                lighting = {
                    ClockTime = 0, Brightness = 0,
                    OutdoorAmbient = { 0, 0, 0 },
                    Ambient = { 20, 20, 25 },
                    FogEnd = 2000, FogColor = { 0, 0, 0 },
                    GlobalShadows = false,
                },
            },
            ice = {
                paletteClass = "palette-glacier-ice",
                terrainStyle = "outdoor",
                terrainWall = "Glacier",
                terrainWallMix = "Rock",
                terrainFloor = "Snow",
                partWall = "Ice",
                partFloor = "Glacier",
                doorWallClass = "ice-wall-solid",
                skipLights = true,
                lighting = {
                    ClockTime = 14, Brightness = 1.5,
                    OutdoorAmbient = { 140, 160, 190 },
                    Ambient = { 80, 90, 110 },
                    FogEnd = 1600, FogColor = { 180, 200, 220 },
                    GlobalShadows = true,
                },
            },
            meadow = {
                paletteClass = "palette-highland-meadow",
                terrainStyle = "outdoor",
                terrainWall = "Slate",
                terrainFloor = "Grass",
                partWall = "Cobblestone",
                partFloor = "Grass",
                doorWallClass = "outdoor-wall-solid",
                skipLights = true,
                lighting = {
                    ClockTime = 14, Brightness = 2,
                    OutdoorAmbient = { 160, 170, 140 },
                    Ambient = { 90, 100, 80 },
                    FogEnd = 2400, FogColor = { 170, 190, 160 },
                    GlobalShadows = true,
                },
            },
            desert = {
                paletteClass = "palette-desert-ruins",
                terrainStyle = "outdoor",
                terrainWall = "Sandstone",
                terrainFloor = "Sand",
                partWall = "Limestone",
                partFloor = "Sandstone",
                doorWallClass = "outdoor-wall-solid",
                skipLights = true,
                lighting = {
                    ClockTime = 12, Brightness = 3,
                    OutdoorAmbient = { 200, 180, 140 },
                    Ambient = { 120, 110, 85 },
                    FogEnd = 3000, FogColor = { 220, 200, 160 },
                    GlobalShadows = true,
                },
            },
            sewer = {
                paletteClass = "palette-sewer-works",
                terrainWall = "Concrete",
                terrainFloor = "Mud",
                partWall = "CorrodedMetal",
                partFloor = "Metal",
                lightType = "PointLight",
                lightStyle = "cave-point-light",
                lighting = {
                    ClockTime = 0, Brightness = 0,
                    OutdoorAmbient = { 0, 0, 0 },
                    Ambient = { 10, 15, 8 },
                    FogEnd = 1200, FogColor = { 15, 20, 10 },
                    GlobalShadows = false,
                },
            },
            crystal = {
                paletteClass = "palette-crystal-cave",
                terrainWall = "Basalt",
                terrainFloor = "Salt",
                partWall = "Glass",
                partFloor = "Neon",
                lightType = "PointLight",
                lightStyle = "cave-point-light",
                lighting = {
                    ClockTime = 0, Brightness = 0,
                    OutdoorAmbient = { 0, 0, 0 },
                    Ambient = { 25, 15, 35 },
                    FogEnd = 1400, FogColor = { 10, 5, 20 },
                    GlobalShadows = false,
                },
            },
            village = {
                paletteClass = "palette-village-green",
                terrainStyle = "outdoor",
                terrainWall = "Pavement",
                terrainFloor = "Grass",
                partWall = "Brick",
                partFloor = "WoodPlanks",
                doorWallClass = "outdoor-wall-solid",
                skipLights = true,
                lighting = {
                    ClockTime = 15, Brightness = 2,
                    OutdoorAmbient = { 150, 155, 130 },
                    Ambient = { 85, 90, 75 },
                    FogEnd = 2800, FogColor = { 180, 190, 170 },
                    GlobalShadows = true,
                },
            },
            mountain = {
                paletteClass = "palette-highland-meadow",
                terrainStyle = "outdoor",
                terrainWall = "Rock",
                terrainFloor = "Rock",
                partWall = "Slate",
                partFloor = "Grass",
                lightType = "PointLight",
                lightStyle = "cave-torch-light",
                lighting = {
                    ClockTime = 14, Brightness = 1,
                    OutdoorAmbient = { 78, 83, 88 },
                    Ambient = { 49, 52, 56 },
                    FogEnd = 4000, FogColor = { 180, 190, 210 },
                    GlobalShadows = true,
                },
            },
        },

        wiring = {
            -- Hub-and-spoke: orchestrator calls each node sequentially
            -- WorldMapOrchestrator → WorldBridge → DungeonOrchestrator → pipeline nodes
            WorldMapOrchestrator    = { "WorldBridge", "DungeonOrchestrator", "MiniMap" },
            WorldBridge             = { "DungeonOrchestrator", "WorldMapOrchestrator" },
            DungeonOrchestrator     = {
                "InventoryNode", "SplinePlannerNode", "BlockoutNode",
                "TerrainPainterNode", "MeshTerrainPainterNode", "RockScatterNode",
                "MountainRoomPlacer", "ShellBuilder", "DoorPlanner",
                "TrussBuilder", "LightBuilder", "Materializer",
                "IceTerrainPainter", "DoorCutter",
                "DependencyResolver", "PassageNode", "ItemNode",
                "WorldMapOrchestrator", "WorldBridge",
            },
            InventoryNode           = { "DungeonOrchestrator" },
            SplinePlannerNode       = { "DungeonOrchestrator" },
            BlockoutNode            = { "DungeonOrchestrator" },
            TerrainPainterNode      = { "DungeonOrchestrator" },
            MeshTerrainPainterNode  = { "DungeonOrchestrator" },
            RockScatterNode         = { "DungeonOrchestrator" },
            MountainRoomPlacer      = { "DungeonOrchestrator" },
            ShellBuilder            = { "DungeonOrchestrator" },
            DoorPlanner             = { "DungeonOrchestrator" },
            TrussBuilder            = { "DungeonOrchestrator" },
            LightBuilder            = { "DungeonOrchestrator" },
            Materializer            = { "DungeonOrchestrator" },
            IceTerrainPainter       = { "DungeonOrchestrator" },
            DoorCutter              = { "DungeonOrchestrator" },
            DependencyResolver      = { "DungeonOrchestrator" },
            PassageNode             = { "DungeonOrchestrator" },
            ItemNode                = { "DungeonOrchestrator" },
            BackpackToolbar         = {},
            MiniMap                 = { "WorldMapOrchestrator" },
        },
    },

    -- WorldBridge manages chunked world loading/unloading
    WorldBridge = {
        computeTarget = "warren",
        loadRadius = 2,        -- chunks around player to keep loaded (5x5 = 25)
        unloadRadius = 4,      -- chunks beyond this get unloaded
        pollInterval = 1.0,    -- seconds between position checks
        mapWidth = 4000,
        mapDepth = 4000,
        groundY = 0,
    },

    -- DungeonOrchestrator is now a pipeline node (receives everything via signal)
    DungeonOrchestrator = {
        -- "warren" = VPS compute (Lune server), "roblox" = local compute on game server
        computeTarget = "warren",
        -- "voxel" = Roblox terrain voxels (4-stud resolution)
        -- "mesh"  = EditableMesh chunks (smooth, 8-stud vertex spacing)
        terrainRenderer = "voxel",
    },

    ---------------------------------------------------------------------------
    -- Per-node config (JavaFX "type selectors" — Level 2)
    ---------------------------------------------------------------------------

    InventoryNode = {
        mapWidth = 4000,
        mapDepth = 4000,
    },

    SplinePlannerNode = {
        mapWidth = 4000,
        mapDepth = 4000,
        origin = { 0, 0, 0 },
    },

    BlockoutNode = {
        showBlockout = false,
        groundY = 0,
    },

    TerrainPainterNode = {
        mapWidth = 4000,
        mapDepth = 4000,
        groundY = 0,
        tileSize = 512,
        noiseAmplitude = 50,    -- studs displacement (0 = off)
        noiseScale1 = 400,     -- octave 1 wavelength
        noiseScale2 = 160,     -- octave 2 wavelength
        noiseRatio = 0.65,     -- octave 1 weight
    },

    MeshTerrainPainterNode = {
        mapWidth = 4000,
        mapDepth = 4000,
        groundY = 0,
        chunkSize = 512,
        vertexSpacing = 8,
        maxConcurrency = 8,
    },

    MountainRoomPlacer = {
        burialFrac = 0.5,
        maxRooms = 800,
        downwardBias = 50,
        scaleRange = { min = 4, max = 10, minY = 4, maxY = 7 },
        groundY = 0,
    },

    RockScatterNode = {
        groundY = 0,
    },

    MountainRoomMasser = {
        falseEntries = 6,
        caveSystems = 3,
        falseEntryMaxRooms = 3,
        caveMinRooms = 6,
        caveMaxRooms = 15,
        inwardBias = 60,
        scaleRange = { min = 4, max = 10, minY = 4, maxY = 7 },
    },

    RoomMasser = {
        mainPathLength = 8,
        spurCount = 4,
        verticalChance = 30,
        minVerticalRatio = 0.2,
        scaleRange = { min = 4, max = 12, minY = 4, maxY = 8 },
        origin = { 0, 40, 0 },
    },

    DependencyResolver = {
        gateCountMin = 1,       -- min gates on critical path
        gateCountMax = 3,       -- max gates on critical path
        maxKeyDistance = 4,     -- max rooms between item and its gate (higher = harder)
        branchGateChance = 0.3, -- probability of gating a branch entrance
    },

    PassageNode = {
        autoClose = 3,       -- seconds after last player leaves zone to re-close
        frameModel = "door_frame",  -- Model name in ReplicatedStorage.Assets (nil = no frame)
        frameBorder = 3,     -- studs of border around opening
    },

    TrussBuilder = {
        floorThreshold = 13,
    },

    TerrainPainter = {
        wallMaterial = "Rock",
        floorMaterial = "CrackedLava",
        noiseScale = 16,
        noiseThreshold = 0.35,
        patchScale = 24,
        patchThreshold = 0.4,
    },

    ---------------------------------------------------------------------------
    -- Shared defaults (JavaFX "user-agent defaults" — Level 1)
    ---------------------------------------------------------------------------

    defaults = {
        wallThickness = 2,
        doorSize = 24,
        baseUnit = 10,
    },

    ---------------------------------------------------------------------------
    -- ClassResolver cascade (future themes — Levels 3 & 4)
    ---------------------------------------------------------------------------

    definitions = {
        classes = {},
        ids = {},
    },
}
