--!nonstrict
-- Owns "where is everyone" in the one continuous Adventure world: builds it from
-- WorldLayout at start, tracks which area each player stands in (for the banner and
-- lighting), spawn points and dialogue lookups. One Roblox server = one party.
-- TODO(port): quest-gated passages (adventure.exits() reasons) as blockers on trails,
-- the Last Caravan opening, Dunmere hub geometry, dungeon encounters/waves, recovery
-- points and wipes, DataStore saves, shrine travel and the Soul Transport Crystal.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Coord = require(Shared.Coord)
local Data = require(Shared.Data)
local Remotes = require(Shared.Remotes)
local WorldLayout = require(Shared.WorldLayout)
local Sizes = require(Shared.Sizes)

local State = require(script.Parent.State)
local WorldBuilder = require(script.Parent.WorldBuilder)
local AreaBuilder = require(script.Parent.AreaBuilder)
local Interactions = require(script.Parent.Interactions)
local Progress = require(script.Parent.Progress)
local Opening = require(script.Parent.OpeningService)

local Adventure = Data.Adventure

local WorldService = {}

local function announce(player: Player, areaId: string)
	local info = State.areas[areaId]
	State.discovered[areaId] = true
	Remotes.get("AreaChanged"):FireClient(player, areaId, Adventure.AREAS[areaId].name, info.region)
end

-- Respawn (and first spawn): at the start of the world until inns/recovery points are ported.
function WorldService.spawnPlayer(player: Player)
	local character = player.Character
	if not character or not State.spawn then
		return
	end
	local count = #Players:GetPlayers()
	local angle = ((table.find(Players:GetPlayers(), player) or 1) / math.max(count, 1)) * math.pi * 2
	local offset = count > 1 and Vector3.new(math.cos(angle) * 4, 0, math.sin(angle) * 4) or Vector3.zero
	local intro = Opening.spawnFor(player, table.find(Players:GetPlayers(), player) or 1)
	character:PivotTo(CFrame.new(intro or ((State.respawn[player] or State.spawn) + offset + Vector3.new(0, 2, 0))))
	State.lastSafe[player] = nil
	State.playerArea[player] = nil
	task.defer(function()
		local id = State.playerArea[player] or WorldService.areaOf(player)
		if id then
			State.playerArea[player] = id
			announce(player, id)
		end
	end)
end

function WorldService.areaOf(player: Player): string?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local p = root.Position
	return WorldLayout.areaAt(State.layout, p.X, p.Y, p.Z)
end

local function trackPlayers()
	while true do
		for _, player in Players:GetPlayers() do
			local id = WorldService.areaOf(player)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			-- Backup for the client-side level barriers: under-level players are sent back.
			if id and root and Progress.get(player).level < Progress.requiredLevel(id) then
				local back = State.lastSafe[player] or State.spawn
				player.Character:PivotTo(CFrame.new(back + Vector3.new(0, 3, 0)))
				Remotes.get("Notify"):FireClient(player, ("%s requires level %d."):format(Adventure.AREAS[id].name, Progress.requiredLevel(id)))
				id = nil
			elseif root and not id then
				State.lastSafe[player] = root.Position
			elseif root and id then
				State.lastSafe[player] = root.Position
			end
			-- Between areas (trails, wilderness) the last area's name and mood stay on screen.
			if id and id ~= State.playerArea[player] then
				State.playerArea[player] = id
				announce(player, id)
			end
		end
		task.wait(0.4)
	end
end

function WorldService.start()
	local layout = WorldLayout.compute({
		AREAS = Adventure.AREAS,
		LARGE_AREAS = Sizes.table(Adventure.AREAS, Adventure.LARGE_AREAS, Config.DEFAULT_AREA_PX),
		OPEN_LINKS = Config.OPEN_LINKS,
		EXIT_OFFSETS = Adventure.EXIT_OFFSETS,
		DEFAULT_PX = Config.DEFAULT_AREA_PX,
	}, {
		scale = Config.WORLD_STUDS_PER_PX,
		cellPx = Config.WORLD_CELL_PX,
		caveDepth = Config.CAVE_DEPTH,
		floorHeight = Config.FLOOR_HEIGHT,
		slope = Config.RAMP_SLOPE,
		rampWidth = Config.TRAIL_WIDTH,
		stub = Config.TRAIL_STUB,
		gapMin = Config.TRAIL_GAP_MIN,
		gapVar = Config.TRAIL_GAP_VAR,
		unlinkedGap = Config.UNLINKED_GAP,
	})
	State.layout = layout
	State.areas = WorldBuilder.build(layout, {
		onFeature = Interactions.handle,
	})

	-- Waystones (village stones + travel shrines) for the travel menu.
	for areaId, info in State.areas do
		for _, feature in AreaBuilder.features(areaId, info.widthPx, info.heightPx) do
			-- Keys can repeat across areas (e.g. a runner in Oakvale and in Dunmere): Oakvale wins for
			-- the quest compass; Dunmere targets are resolved per area (Dunmere.position).
			local at = Coord.toWorld(info.origin, feature.x, feature.y, 0)
			State.featurePosByArea[areaId] = State.featurePosByArea[areaId] or {}
			State.featurePosByArea[areaId][feature.key] = at
			if State.featurePos[feature.key] == nil or areaId == "home" then
				State.featurePos[feature.key] = at
			end
			if feature.kind == "waystone" or feature.kind == "travel_shrine" then
				State.waystones[feature.key] = {
					id = feature.key,
					name = feature.name,
					area = areaId,
					shrine = feature.shrine,
					pos = Coord.toWorld(info.origin, feature.x, feature.y, 0),
				}
			end
		end
	end

	do
		local world = workspace:FindFirstChild("World")
		local parts = 0
		if world then
			for _, d in world:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
				end
			end
		end
		print(("[Gauntlet] world built: %d parts (%d areas, %.0fx%.0f studs)"):format(parts, #layout.order, layout.bounds.maxX - layout.bounds.minX, layout.bounds.maxZ - layout.bounds.minZ))
	end

	-- Backdrop is cosmetic: a failure here must never stop the world from starting.
	local ok, err = pcall(function()
		require(script.Parent.Backdrop).build(layout.bounds)
	end)
	if not ok then
		warn("[Gauntlet] backdrop failed: " .. tostring(err))
	end

	local start = State.areas[Config.START_AREA]
	State.spawn = Coord.toWorld(start.origin, start.widthPx / 2, start.heightPx * 0.55, 4)

	Players.PlayerRemoving:Connect(function(player)
		State.playerArea[player] = nil
		State.lastSafe[player] = nil
	end)
	task.spawn(trackPlayers)
end

return WorldService
