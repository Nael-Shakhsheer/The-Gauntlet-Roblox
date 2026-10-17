--!nonstrict
-- Finite dungeon encounters ported from dungeons.py:
--   Rootwater cave: ring the seal in the troll den -> den is sealed until the Cave Troll falls ->
--     rubble across the far (clearing) opening is cleared permanently.
--   Briarwatch tower: floor bells -> wave 1/2 (3 s break) per floor 1-2, floor 3 = Minotaur Captain +
--     serpent guards. Floor N+1 stays closed until floor N is cleared; summit opens the bridge descent.
-- "Sealed" = players who joined the attempt are pushed back if they walk out; the attempt resets if
-- every participant falls or leaves. Completion lives in State.claimed ("dg:cave", "dg:tower:fN").

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Data = require(Shared.Data)
local Coord = require(Shared.Coord)
local Make = require(Shared.Make)
local Palette = require(Shared.Palette)
local Remotes = require(Shared.Remotes)
local WorldLayout = require(Shared.WorldLayout)

local State = require(script.Parent.State)
local Progress = require(script.Parent.Progress)
local EnemyService = require(script.Parent.EnemyService)

local D = Data.Dungeons

local DungeonService = {}

local BOSS = {
	cave_heart = { kind = "troll", name = "Rootwater Cave Troll", scale = 1.9, xPx = 480, yPx = 245 },
	tower_3 = { kind = "minotaur", name = "Briarwatch Minotaur Captain", scale = 1.9, xPx = 480, yPx = 245 },
	cellar = { kind = "troll", name = "Blighted Overseer", scale = 1.9, xPx = 570, yPx = 210, hp = 420, damage = 9, speed = 65 },
}
local GUARD_SPOTS = { { 160, 130 }, { 800, 130 } }
local BELL_RADIUS = 60 -- studs: every living hunter must stand this close to the bell
local BREAK_SECONDS = 3

local attempts = { cave = nil, tower = nil } -- { area, wave, ids = {id=true}, members = {Player=true}, serial, emptySince }
local serial = 0
local rubble = {} -- "cave" | "tower" -> Part

local function notify(player: Player, text: string)
	Remotes.get("Notify"):FireClient(player, text)
end

local function party(fn)
	for _, p in Players:GetPlayers() do
		fn(p)
	end
end

local function say(text: string)
	party(function(p)
		notify(p, text)
	end)
end

local function dungeonOf(areaId: string): string?
	if areaId == "cellar" then
		return "cellar"
	end
	local a = D.AREAS[areaId]
	return a and a.dungeon
end

local function floorOf(areaId: string): number?
	local a = D.AREAS[areaId]
	return a and a.floor
end

local function claimedKey(dungeon: string, floor: number?)
	if dungeon == "cave" or dungeon == "cellar" then
		return "dg:" .. dungeon
	end
	return "dg:tower:f" .. tostring(floor)
end

function DungeonService.done(dungeon: string): boolean
	return State.claimed[dungeon == "cave" and "dg:cave" or "dg:tower:f3"] == true
end

local function areaAt(position: Vector3): string?
	return WorldLayout.areaAt(State.layout, position.X, position.Y, position.Z)
end

local function alive(player: Player): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and not State.fallen[player]
end

local function rootOf(player: Player): BasePart?
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

-- Where a feature of `kind` sits (dungeon_begin in the area).
local function beginSpot(areaId: string): Vector3?
	local info = State.areas[areaId]
	local list = D.FEATURES[areaId] or {}
	if areaId == "cellar" then
		list = { { "cellar_begin", "", 570, 290, "dungeon_begin" } }
	end
	for _, f in list do
		if f[5] == "dungeon_begin" then
			local gx, gy = Coord.scaleToArea(f[3], f[4], info.widthPx, info.heightPx)
			return Coord.toWorld(info.origin, gx, gy, 0) + Vector3.new(0, 3, 0)
		end
	end
	return nil
end

-- ---------------------------------------------------------------- rubble

local function gapPoint(rect, gap)
	if gap.edge == "west" then
		return rect.left, gap.along, "x"
	elseif gap.edge == "east" then
		return rect.right, gap.along, "x"
	elseif gap.edge == "north" then
		return gap.along, rect.top, "z"
	end
	return gap.along, rect.bottom, "z"
end

local function buildRubble(dungeon: string, areaId: string, towardId: string, height: number)
	local layout = State.layout
	local rect, target = layout.areas[areaId], layout.areas[towardId]
	local gaps = layout.gaps[areaId]
	if not rect or not target or not gaps then
		return
	end
	local tx, tz = (target.left + target.right) / 2, (target.top + target.bottom) / 2
	local best, bx, bz, axis, bd
	for _, gap in gaps do
		local x, z, a = gapPoint(rect, gap)
		local d = (x - tx) ^ 2 + (z - tz) ^ 2
		if not bd or d < bd then
			bd, best, bx, bz, axis = d, gap, x, z, a
		end
	end
	if not best then
		return
	end
	local inward = (best.edge == "west" or best.edge == "north") and 3 or -3
	local span = Config.TRAIL_WIDTH + 8
	local size, pos
	if axis == "x" then
		size = Vector3.new(3, height, span)
		pos = Vector3.new(bx + inward, rect.y + height / 2, bz)
	else
		size = Vector3.new(span, height, 3)
		pos = Vector3.new(bx, rect.y + height / 2, bz + inward)
	end
	local world = workspace:FindFirstChild("World") or workspace
	local folder = world:FindFirstChild("Dungeons") or Instance.new("Folder")
	folder.Name = "Dungeons"
	folder.Parent = world
	local part = Make.part({
		Name = dungeon == "cave" and "TrollRubble" or "SummitBarricade",
		Size = size,
		Position = pos,
		Color = dungeon == "cave" and Color3.fromRGB(86, 80, 74) or Color3.fromRGB(110, 86, 62),
		Material = dungeon == "cave" and Enum.Material.Slate or Enum.Material.Wood,
	}, folder)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 44)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 80
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.25
	label.BackgroundColor3 = Palette.UI.ink
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextWrapped = true
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.Text = dungeon == "cave" and "Rubble - the troll holds this passage. Enter from the road."
		or "Barricade - clear all three floors to open the descent."
	label.Parent = gui
	rubble[dungeon] = part
end

local function openRoute(dungeon: string)
	local part = rubble[dungeon]
	if not part then
		return
	end
	rubble[dungeon] = nil
	part.CanCollide = false
	TweenService:Create(part, TweenInfo.new(1.2), { Transparency = 1, Size = part.Size * Vector3.new(1, 0.1, 1) }):Play()
	task.delay(1.4, function()
		part:Destroy()
	end)
end

-- ---------------------------------------------------------------- encounters

local function livingPlayersIn(areaId: string)
	local out = {}
	for _, p in Players:GetPlayers() do
		local root = rootOf(p)
		if root and alive(p) and areaAt(root.Position) == areaId then
			table.insert(out, p)
		end
	end
	return out
end

local function clearAttempt(dungeon: string)
	local a = attempts[dungeon]
	if a then
		for id in a.ids do
			EnemyService.remove(id)
		end
	end
	attempts[dungeon] = nil
end

local function spawnWave(dungeon: string)
	local a = attempts[dungeon]
	local areaId = a.area
	a.ids = {}
	local n = math.max(1, #Players:GetPlayers())
	local function add(id, kind, x, y, opts)
		id = ("%s-d%d-%s"):format(areaId, a.serial, id)
		if EnemyService.spawnFixed(areaId, id, kind, x, y, opts) then
			a.ids[id] = true
		end
	end
	local boss = BOSS[areaId]
	if boss then
		add("boss", boss.kind, boss.xPx, boss.yPx, { boss = true, name = boss.name, scale = boss.scale, bossKey = "dungeon_" .. areaId, hp = boss.hp, damage = boss.damage, speed = boss.speed })
		if areaId == "tower_3" then
			for i = 1, math.min(2, n) do
				add("guard" .. i, "serpent", GUARD_SPOTS[i][1], GUARD_SPOTS[i][2])
			end
		end
	else
		local kinds = D.FLOOR_PACKS[areaId][a.wave]
		local spots = D.FLOOR_SPOTS[areaId]
		for i = 1, #kinds + n - 1 do
			local spot = spots[(i - 1) % #spots + 1]
			add(("w%d-%d"):format(a.wave, i), kinds[(i - 1) % #kinds + 1], spot[1], spot[2])
		end
	end
end

function DungeonService.begin(player: Player, feature)
	local areaId = feature.area
	local dungeon = dungeonOf(areaId)
	if not dungeon then
		return
	end
	local floor = floorOf(areaId)
	if State.claimed[claimedKey(dungeon, floor)] then
		notify(player, dungeon ~= "tower" and "That guardian is already defeated." or ("Floor %d is already cleared."):format(floor))
		return
	end
	if attempts[dungeon] then
		notify(player, "The encounter is already underway.")
		return
	end
	local spot = beginSpot(areaId)
	for _, p in Players:GetPlayers() do
		local root = rootOf(p)
		if alive(p) and (not root or (root.Position - spot).Magnitude > BELL_RADIUS) then
			notify(player, "Gather all hunters at the bell or seal to begin.")
			return
		end
	end
	serial += 1
	local members = {}
	for _, p in livingPlayersIn(areaId) do
		members[p] = true
	end
	attempts[dungeon] = { area = areaId, wave = 1, ids = {}, members = members, serial = serial, spot = spot }
	spawnWave(dungeon)
	say(dungeon == "cellar" and "The pump chamber seals! Dodge the Overseer's marked attacks."
		or dungeon == "cave" and "The den seals. Defeat the Rootwater Cave Troll!"
		or ("Floor %d: the bell tolls. Stairs sealed until the floor is cleared."):format(floor))
end

local function reward(dungeon: string, xp: number, runes: number, potion: string?)
	local a = attempts[dungeon]
	for _, p in Players:GetPlayers() do
		if not a or a.members[p] or alive(p) then
			Progress.addXp(p, xp)
			Progress.addRunes(p, runes)
			if potion then
				Progress.givePotion(p, potion, 1)
			end
		end
	end
end

local function waveCleared(dungeon: string)
	local a = attempts[dungeon]
	local areaId = a.area
	local floor = floorOf(areaId)
	if dungeon == "tower" and floor ~= 3 and a.wave < 2 then
		a.wave += 1
		a.ids = {}
		say(("Floor %d - wave %d cleared. Next wave in %d seconds."):format(floor, a.wave - 1, BREAK_SECONDS))
		local mine = a
		task.delay(BREAK_SECONDS, function()
			if attempts.tower == mine then
				spawnWave("tower")
			end
		end)
		return
	end
	State.claimed[claimedKey(dungeon, floor)] = true
	if dungeon == "cellar" then
		reward(dungeon, 200, 170, "healing_draught")
		attempts.cellar = nil
		say("The Blighted Overseer falls. The pump chamber unseals.")
		if DungeonService.completed then
			DungeonService.completed("cellar")
		end
	elseif dungeon == "cave" then
		reward(dungeon, 160, 140, "mana_draught")
		attempts.cave = nil
		openRoute("cave")
		say("Rootwater passage complete - the road and clearing are joined again.")
	elseif floor == 3 then
		reward(dungeon, 260, 220, "healing_draught")
		attempts.tower = nil
		openRoute("tower")
		say("Briarwatch tower complete - the descent to the bridge is open.")
	else
		reward(dungeon, 60 + 30 * floor, 40 + 20 * floor, "warding_tonic")
		attempts.tower = nil
		say(("Floor %d cleared. Stairs are open, or return down to camp."):format(floor))
	end
end

function DungeonService.onKill(enemy)
	for dungeon, a in attempts do
		if a.ids[enemy.id] then
			a.ids[enemy.id] = nil
			if next(a.ids) == nil then
				waveCleared(dungeon)
			end
			return
		end
	end
end

-- Treasure crates in the cave (cave_supplies / cave_survey).
local TREASURE = { cave_supplies = { runes = 40, potion = "healing_draught" }, cave_survey = { runes = 64, potion = "mana_draught" } }

function DungeonService.handle(player: Player, feature): boolean
	local t = TREASURE[feature.key]
	if t then
		if State.claimed[feature.key] then
			notify(player, "Already looted.")
			return true
		end
		State.claimed[feature.key] = true
		for _, p in Players:GetPlayers() do
			Progress.addRunes(p, t.runes)
			Progress.addXp(p, 30)
			Progress.givePotion(p, t.potion, 1)
		end
		say(feature.key == "cave_survey" and "Surveyor's notes: this passage once joined the road and clearing; the troll holds the eastern opening."
			or "Old cave supplies recovered.")
		return true
	end
	if feature.kind == "dungeon_begin" then
		DungeonService.begin(player, feature)
		return true
	end
	return false
end

-- ---------------------------------------------------------------- enforcement loop

local function push(player: Player, spot: Vector3, text: string)
	local root = rootOf(player)
	if root then
		player.Character:PivotTo(CFrame.new(spot + Vector3.new(0, 3, 0)))
	end
	notify(player, text)
end

local function loop()
	while true do
		task.wait(0.5)
		for dungeon, a in attempts do
			local present = 0
			for _, p in Players:GetPlayers() do
				local root = rootOf(p)
				local here = root and areaAt(root.Position) or nil
				if a.members[p] then
					if not alive(p) then
						a.members[p] = nil
					elseif here ~= a.area then
						push(p, a.spot, "The way out is sealed until the encounter ends.")
						present += 1
					else
						present += 1
					end
				elseif root and here == a.area and alive(p) then
					a.members[p] = true
					present += 1
				end
			end
			if present == 0 then
				a.empty = (a.empty or 0) + 0.5
				if a.empty >= 6 then
					clearAttempt(dungeon)
					say("The encounter fades. Return to the bell to try again.")
				end
			else
				a.empty = 0
			end
		end
		-- Tower floors open one at a time; descending is always allowed.
		for _, p in Players:GetPlayers() do
			local root = rootOf(p)
			local here = root and alive(p) and areaAt(root.Position)
			local floor = here and floorOf(here)
			if floor and floor > 1 and not State.claimed["dg:tower:f" .. (floor - 1)] then
				local below = "tower_" .. (floor - 1)
				local spot = beginSpot(below)
				if spot then
					push(p, spot, "Clear the previous floor before using these stairs.")
				end
			end
		end
	end
end

function DungeonService.start()
	local previous = EnemyService.onKill
	EnemyService.onKill = function(enemy, attacker)
		if previous then
			previous(enemy, attacker)
		end
		DungeonService.onKill(enemy)
	end
	if not State.claimed["dg:cave"] then
		buildRubble("cave", "cave_heart", "clearing", Config.CAVE_DEPTH - 4)
	end
	if not State.claimed["dg:tower:f3"] then
		buildRubble("tower", "tower_3", "bridge", 22)
	end
	task.spawn(loop)
end

-- Called after saved world progress is merged: remove barriers of dungeons already completed.
function DungeonService.refresh()
	if State.claimed["dg:cave"] then
		openRoute("cave")
	end
	if State.claimed["dg:tower:f3"] then
		openRoute("tower")
	end
end

return DungeonService
