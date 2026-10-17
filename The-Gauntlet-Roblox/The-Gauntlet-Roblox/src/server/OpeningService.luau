--!nonstrict
-- The Last Caravan opening (opening.py). A new world starts on a separate caravan road west of the map:
--   arrival (8 s) -> road wolves -> flank pack (serpent + wolves) -> dragon strike message ->
--   gate opens -> everyone reaches the gold muster circle -> Oakvale + "caravan_aftermath" dialogue.
-- No XP/runes/drops from these fights. Exhausted guard "support" arrows (budget 28 dmg) help weak kits.
-- Completion = State.claimed["opening"] (persists). Existing saves (any quest progress) skip it.
-- Simplified: mid-opening progress is not saved (a restart replays it); dead players re-enter the arena.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Data = require(Shared.Data)
local Coord = require(Shared.Coord)
local Make = require(Shared.Make)
local Palette = require(Shared.Palette)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.State)
local EnemyService = require(script.Parent.EnemyService)

local Opening = {}

local W_PX, H_PX = 1280, 720
local MUSTER = { 1040, 150 }
local MUSTER_REACH_PX = 100
local ROAD_SITES = { { 110, 330 }, { 240, 600 }, { 800, 635 }, { 150, 540 }, { 760, 80 }, { 180, 180 } }
local FLANK_SITES = { { 820, 80 }, { 1160, 430 }, { 140, 480 }, { 800, 635 }, { 180, 180 }, { 240, 600 } }
local GUARD_PX = { 650, 340 }

local origin -- Vector3 world position of arena px (0,0)
local run -- { phase, startedAt, spawned, support, supportAt, ids, serial, eventDone }
local serial = 0
local built = false

local function notify(text: string)
	for _, p in Players:GetPlayers() do
		Remotes.get("Notify"):FireClient(p, text)
	end
end

local function px(x: number, y: number, h: number?): Vector3
	return Coord.toWorld(origin, x, y, h or 0)
end

local function alive(p: Player): boolean
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and not State.fallen[p]
end

function Opening.shouldRun(): boolean
	if true then
		return false -- opening removed (see Opening.start)
	end
	if State.claimed.opening then
		return false
	end
	for _, v in State.quests do
		if v ~= "new" then
			return false
		end
	end
	return true
end

function Opening.active(): boolean
	return built and Opening.shouldRun()
end

function Opening.musterPos(): Vector3?
	return origin and px(MUSTER[1], MUSTER[2], 0) or nil
end

-- Where a player spawns while the opening is on (nil otherwise).
function Opening.spawnFor(player: Player, index: number): Vector3?
	if not Opening.active() then
		return nil
	end
	return px(620 + (index - 1) * 32, 470, 2)
end

local function complete()
	State.claimed.opening = true
	local old = run
	run = nil
	if old then
		for id in old.ids do
			EnemyService.remove(id)
		end
	end
	local page = Data.Adventure.PAGES.caravan_aftermath
	task.defer(function()
		local ok, Quests = pcall(require, script.Parent.Quests)
		if ok then
			Quests.broadcast()
		end
	end)
	for _, p in Players:GetPlayers() do
		if p.Character and State.spawn then
			p.Character:PivotTo(CFrame.new(State.spawn + Vector3.new(0, 3, 0)))
		end
		State.playerArea[p] = nil
		Remotes.get("Dialogue"):FireClient(p, page[1], page[2])
	end
	notify("Caravan survivors reached Oakvale. Follow the missing hunter's tracks on the Southern road.")
	local ok, Quests = pcall(require, script.Parent.Quests)
	if ok then
		Quests.broadcast()
	end
end

local function spawnPack(second: boolean)
	local n = math.max(1, #Players:GetPlayers())
	local count = (second and 3 or 2) + (n - 1)
	local sites = second and FLANK_SITES or ROAD_SITES
	for i = 1, count do
		local kind = (second and i == 1) and "serpent" or "wolf"
		local id = ("caravan-%d-%s-%d"):format(run.serial, second and "flank" or "road", i)
		local site = sites[(i - 1) % #sites + 1]
		if EnemyService.spawnFixed("caravan", id, kind, site[1], site[2], {
			name = kind == "serpent" and "Displaced Serpent" or "Displaced Wolf",
			hp = kind == "wolf" and 48 or 55,
			damage = 4,
			speed = 68,
			noReward = true,
			noLeash = true,
		}) then
			run.ids[id] = true
		end
	end
end

local function anyLeft(): boolean
	for id in run.ids do
		if State.enemies[id] then
			return true
		end
	end
	return false
end

local function inArena(p: Player): boolean
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local a = State.areas.caravan.rect
	return root.Position.X >= a.left and root.Position.X <= a.right and root.Position.Z >= a.top and root.Position.Z <= a.bottom
end

local function newRun(phase: string)
	serial += 1
	run = { phase = phase, startedAt = os.clock(), spawned = false, support = 0, supportAt = 0, ids = {}, serial = serial, event = false, creaked = false }
end

local function reset()
	if run then
		for id in run.ids do
			EnemyService.remove(id)
		end
	end
	newRun("arrival")
	for i, p in Players:GetPlayers() do
		if p.Character then
			p.Character:PivotTo(CFrame.new(px(620 + (i - 1) * 32, 470, 3)))
		end
		State.playerArea[p] = nil
	end
	notify("The road is lost. Hold the line again!")
end

local function _tick()
	local present = {}
	for _, p in Players:GetPlayers() do
		if inArena(p) then
			table.insert(present, p)
		end
	end
	if #present == 0 then
		return
	end
	if not run then
		newRun("arrival")
		notify("Hold the road! Get the wounded through the gate! Defend while the crew loads the wagon.")
	end
	-- Opening enemies always chase.
	for id in run.ids do
		local e = State.enemies[id]
		if e and e.state == "idle" then
			e.state = "chase"
		end
	end
	local now = os.clock()
	local age = now - run.startedAt
	local phase = run.phase
	-- Wipe: every participant down.
	local anyAlive = false
	for _, p in present do
		if alive(p) then
			anyAlive = true
		end
	end
	if not anyAlive and phase ~= "withdrawal" then
		reset()
		return
	end
	if phase == "arrival" then
		if age >= 3 and not run.creaked then
			run.creaked = true
			notify("The wagon creaks under its load...")
		end
		if age >= 8 then
			run.phase, run.startedAt, run.spawned = "first", now, false
		end
	elseif phase == "first" or phase == "second" then
		if not run.spawned and age >= 1.5 then
			run.spawned = true
			spawnPack(phase == "second")
		end
		if phase == "first" and run.spawned and not anyLeft() and age >= 30 then
			run.phase, run.startedAt, run.spawned, run.support = "second", now, false, 0
		elseif phase == "second" then
			if age >= 9 and not run.event then
				run.event = true
				notify("A dragon struck the distant watch! Keep the road clear while the wounded move.")
			end
			if run.spawned and not anyLeft() and age >= 35 then
				run.phase, run.startedAt = "withdrawal", now
				notify("Gate open! Gather at the gold muster circle. Keep everyone together.")
			end
		end
		-- Exhausted guards: bounded line-free arrow support (budget 28 damage).
		if now >= run.supportAt and run.support < 28 then
			local guard = px(GUARD_PX[1], GUARD_PX[2], 3)
			local target = EnemyService.nearestTo(guard, 99)
			if target then
				run.supportAt, run.support = now + 2, run.support + 4
				EnemyService.damage(target, 4, nil)
			end
		end
	elseif phase == "withdrawal" and age >= 20 then
		local muster = px(MUSTER[1], MUSTER[2])
		local reach = MUSTER_REACH_PX * Config.WORLD_STUDS_PER_PX
		local all = true
		for _, p in present do
			local root = p.Character:FindFirstChild("HumanoidRootPart")
			local d = Vector2.new(root.Position.X - muster.X, root.Position.Z - muster.Z).Magnitude
			if not alive(p) or d > reach then
				all = false
			end
		end
		if all then
			complete()
		end
	end
end

-- ------------------------------------------------------------- scenery

local function _build()
	local layout = State.layout
	local b = layout.bounds
	local S = Config.WORLD_STUDS_PER_PX
	local w, h = W_PX * S, H_PX * S
	origin = Vector3.new(b.minX - w - 300, 0, (b.minZ + b.maxZ) / 2 - h / 2)
	local folder = Instance.new("Folder")
	folder.Name = "Caravan"
	folder.Parent = workspace:FindFirstChild("World") or workspace
	local region = Palette.Regions.woodland

	State.areas.caravan = {
		rect = { left = origin.X, right = origin.X + w, top = origin.Z, bottom = origin.Z + h, y = 0, kind = "surface" },
		origin = origin,
		widthPx = W_PX,
		heightPx = H_PX,
		folder = folder,
		region = "woodland",
		kind = "surface",
	}
	local cx, cz = origin.X + w / 2, origin.Z + h / 2
	Make.part({ Name = "CaravanGround", Size = Vector3.new(w + 40, 4, h + 40), Position = Vector3.new(cx, -2, cz), Color = region.ground, Material = Enum.Material.Grass }, folder)
	-- Road across the arena.
	Make.part({ Name = "CaravanRoad", Size = Vector3.new(w, 0.2, 26), Position = Vector3.new(cx, 0.1, origin.Z + 460 * S), Color = Color3.fromRGB(150, 128, 98), Material = Enum.Material.Ground, CanCollide = false }, folder)
	-- Invisible boundary walls.
	local function wall(x, z, sx, sz)
		Make.part({ Name = "Boundary", Size = Vector3.new(sx, 60, sz), Position = Vector3.new(x, 30, z), Transparency = 1, CanCollide = true, CanQuery = false }, folder)
	end
	wall(cx, origin.Z - 2, w + 8, 4)
	wall(cx, origin.Z + h + 2, w + 8, 4)
	wall(origin.X - 2, cz, 4, h + 8)
	wall(origin.X + w + 2, cz, 4, h + 8)
	-- Wagon and gateposts (collision matches opening.py environment()).
	local wagon = Make.part({ Name = "Wagon", Size = Vector3.new(95 * S, 3, 48 * S), Position = px(440 + 47.5, 380 + 24, 2), Color = Color3.fromRGB(122, 88, 56), Material = Enum.Material.Wood }, folder)
	Make.part({ Size = Vector3.new(95 * S, 3.5, 48 * S), Position = px(440 + 47.5, 380 + 24, 5.5), Color = Color3.fromRGB(226, 214, 186), Material = Enum.Material.Fabric, CanCollide = false }, folder)
	for _, wx in { 455, 520 } do
		Make.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 5, 5), CFrame = CFrame.new(px(wx, 428 + 6, 2.5)) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(90), 0, 0), Color = Color3.fromRGB(70, 52, 38), CanCollide = false }, folder)
	end
	for _, gx in { 910, 1135 } do
		Make.part({ Name = "Gatepost", Size = Vector3.new(40 * S, 14, 95 * S), Position = px(gx + 20, 38 + 47.5, 7), Color = Color3.fromRGB(140, 134, 124), Material = Enum.Material.Slate }, folder)
	end
	-- Muster circle.
	Make.part({ Name = "Muster", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, MUSTER_REACH_PX * S * 2, MUSTER_REACH_PX * S * 2), CFrame = CFrame.new(px(MUSTER[1], MUSTER[2], 0.2)) * CFrame.Angles(0, 0, math.rad(90)), Color = Palette.hex("#e8c35a"), Material = Enum.Material.Neon, Transparency = 0.7, CanCollide = false }, folder)
	-- Trees around the rim.
	local rng = Random.new(77)
	for i = 1, 70 do
		local side = rng:NextInteger(1, 4)
		local u, v = rng:NextNumber(), rng:NextNumber() * 0.06
		local x = side <= 2 and origin.X + u * w or side == 3 and origin.X + v * w or origin.X + (1 - v) * w
		local z = side == 1 and origin.Z + v * h or side == 2 and origin.Z + (1 - v) * h or origin.Z + u * h
		local th = 12 + rng:NextNumber() * 8
		Make.part({ Name = "Trunk", Size = Vector3.new(2, th, 2), Position = Vector3.new(x, th / 2, z), Color = Color3.fromRGB(94, 70, 48), Material = Enum.Material.Wood }, folder)
		Make.part({ Name = "Crown", Shape = Enum.PartType.Ball, Size = Vector3.new(11, 11, 11), Position = Vector3.new(x, th + 3, z), Color = region.ground:Lerp(Color3.new(0, 0.2, 0), 0.4), Material = Enum.Material.Grass, CanCollide = false }, folder)
	end
	-- Testing shortcut.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Skip the opening"
	prompt.ObjectText = "Wagon"
	prompt.HoldDuration = 2
	prompt.MaxActivationDistance = 10
	prompt.Parent = wagon
	prompt.Triggered:Connect(function()
		if Opening.active() then
			complete()
		end
	end)
	built = true
end

-- The Last Caravan opening is removed: players start in Oakvale. The module stays as a stub so
-- Quests/WorldService keep their hooks (active() is always false and the arena is never built).
function Opening.start()
	State.claimed.opening = true
end

return Opening
