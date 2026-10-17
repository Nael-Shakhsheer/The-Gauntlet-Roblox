--!nonstrict
-- Shrine rune puzzle (puzzles.py), shared-chamber version.
-- Six rune pads + one totem appear in the shrine glade. Every living hunter gets a target rune.
-- Reading the totem (E) gives the clue for the NEXT hunter's rune (solo: your own), so a party must
-- share clues. When everyone stands on their own rune at once, the guardian awakens.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = require(Shared.Data)
local Coord = require(Shared.Coord)
local Make = require(Shared.Make)
local Palette = require(Shared.Palette)
local Remotes = require(Shared.Remotes)
local WorldLayout = require(Shared.WorldLayout)

local State = require(script.Parent.State)

local P = Data.Puzzles
local ShrinePuzzle = {}
ShrinePuzzle.onSolved = nil

local AREA = "shrine"
local PAD_REACH = 8 -- studs (2D: 34 px)
local COLORS = {
	SUN = Color3.fromRGB(242, 201, 76),
	MOON = Color3.fromRGB(207, 216, 230),
	LEAF = Color3.fromRGB(95, 191, 106),
	FLAME = Color3.fromRGB(232, 85, 61),
	WAVE = Color3.fromRGB(74, 144, 226),
	STAR = Color3.fromRGB(244, 241, 222),
}

local puzzle -- { pads = { {rune, pos} }, totem = Vector3, targets = {UserId = rune}, order = {Players}, folder, last, wrongAt = {} }

local function notify(player: Player, text: string)
	Remotes.get("Notify"):FireClient(player, text)
end

local function say(text: string)
	for _, p in Players:GetPlayers() do
		notify(p, text)
	end
end

local function alive(player: Player): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and not State.fallen[player]
end

local function rootOf(player: Player): BasePart?
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function inShrine(player: Player): boolean
	local root = rootOf(player)
	return root ~= nil and WorldLayout.areaAt(State.layout, root.Position.X, root.Position.Y, root.Position.Z) == AREA
end

function ShrinePuzzle.active(): boolean
	return puzzle ~= nil
end

function ShrinePuzzle.totemPos(): Vector3?
	return puzzle and puzzle.totem or nil
end

-- Hunters taking part: alive and in the glade, in stable order.
local function roster()
	local list = {}
	for _, p in Players:GetPlayers() do
		if alive(p) and inShrine(p) then
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

local function ensureTargets(list)
	for _, p in list do
		if not puzzle.targets[p.UserId] then
			puzzle.targets[p.UserId] = P.RUNES[math.random(#P.RUNES)]
		end
	end
end

local function clueFor(player: Player, list)
	local index = table.find(list, player) or 1
	local recipient = list[index % #list + 1] or player
	return recipient, P.HINTS[puzzle.targets[recipient.UserId]]
end

local function standingRune(player: Player): string?
	local root = rootOf(player)
	if not root then
		return nil
	end
	for _, pad in puzzle.pads do
		local d = Vector2.new(root.Position.X - pad.pos.X, root.Position.Z - pad.pos.Z).Magnitude
		if d <= PAD_REACH then
			return pad.rune
		end
	end
	return nil
end

local function cleanup()
	if puzzle then
		puzzle.folder:Destroy()
		puzzle = nil
	end
	State.flags.puzzle = nil
end

local function solved()
	cleanup()
	say("The runes blaze - the shrine guardian awakens!")
	if ShrinePuzzle.onSolved then
		ShrinePuzzle.onSolved()
	end
end

local function readTotem(player: Player)
	if not puzzle then
		return
	end
	local list = roster()
	if not table.find(list, player) then
		notify(player, "Step into the glade to join the puzzle.")
		return
	end
	ensureTargets(list)
	local recipient, clue = clueFor(player, list)
	local who = recipient == player and "your rune" or (recipient.DisplayName .. "'s rune")
	Remotes.get("Dialogue"):FireClient(player, "Shrine totem", {
		("The totem whispers about %s: %s"):format(who, clue),
		recipient == player and "Stand on the rune that matches." or "Tell them! They must stand on the matching rune while you stand on yours.",
	})
end

local function loop()
	while puzzle do
		task.wait(0.35)
		local list = roster()
		if #list == 0 then
			continue
		end
		ensureTargets(list)
		local all, attempt = true, {}
		for _, p in list do
			local standing = standingRune(p)
			table.insert(attempt, standing or "-")
			if standing ~= puzzle.targets[p.UserId] then
				all = false
				if #list == 1 and standing and os.clock() - (puzzle.wrongAt[p.UserId] or 0) > 2.5 then
					puzzle.wrongAt[p.UserId] = os.clock()
					notify(p, "That rune does not match the clue.")
				end
			end
		end
		if all then
			solved()
			return
		end
		if #list > 1 then
			local key = table.concat(attempt, ",")
			if not key:find("-") and key ~= puzzle.last then
				puzzle.last = key
				say("The group answer does not match. Exchange your totem clues and try again.")
			end
		end
	end
end

function ShrinePuzzle.start(): boolean
	if puzzle then
		return false
	end
	local info = State.areas[AREA]
	if not info then
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = "ShrinePuzzle"
	folder.Parent = workspace:FindFirstChild("World") or workspace

	-- 24 candidate spots as in puzzles.py (960x540 grid) scaled to the area.
	local spots = {}
	for _, y in { 112, 226, 340, 426 } do
		for _, x in { 125, 267, 409, 551, 693, 835 } do
			table.insert(spots, { x, y })
		end
	end
	for i = #spots, 2, -1 do
		local j = math.random(i)
		spots[i], spots[j] = spots[j], spots[i]
	end
	local function world(spot)
		local gx, gy = Coord.scaleToArea(spot[1], spot[2], info.widthPx, info.heightPx)
		return Coord.toWorld(info.origin, gx, gy, 0)
	end
	local pads = {}
	for i, rune in P.RUNES do
		local pos = world(spots[i])
		table.insert(pads, { rune = rune, pos = pos })
		local disc = Make.part({
			Name = "Rune_" .. rune,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, PAD_REACH * 2, PAD_REACH * 2),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = COLORS[rune],
			Material = Enum.Material.Neon,
			Transparency = 0.25,
			CanCollide = false,
		}, folder)
		Make.label(disc, rune, Palette.UI.ink, 4, 120)
	end
	-- Totem: first spot far from every pad.
	local totemPos
	for i = #P.RUNES + 1, #spots do
		local pos = world(spots[i])
		local ok = true
		for _, pad in pads do
			if (pad.pos - pos).Magnitude < PAD_REACH * 2.4 then
				ok = false
			end
		end
		if ok then
			totemPos = pos
			break
		end
	end
	totemPos = totemPos or world(spots[#spots])
	local totem = Make.part({ Name = "Totem", Size = Vector3.new(3, 8, 3), Position = totemPos + Vector3.new(0, 4, 0), Color = Color3.fromRGB(120, 108, 92), Material = Enum.Material.Slate }, folder)
	Make.part({ Size = Vector3.new(2, 1.2, 2), Position = totemPos + Vector3.new(0, 8.6, 0), Color = Palette.Mint, Material = Enum.Material.Neon }, folder)
	Make.label(totem, "Shrine totem", Palette.UI.ink, 5, 140)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Read your totem"
	prompt.ObjectText = "Shrine totem"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = totem
	prompt.Triggered:Connect(readTotem)

	puzzle = { pads = pads, totem = totemPos, targets = {}, folder = folder, last = nil, wrongAt = {} }
	State.flags.puzzle = true
	task.spawn(loop)
	return true
end

return ShrinePuzzle
