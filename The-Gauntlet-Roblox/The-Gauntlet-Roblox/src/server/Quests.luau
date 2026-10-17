--!nonstrict
-- Woodland quest chain from adventure.py (hunter -> bridge -> shrine -> ruins), shared by
-- the whole party. Simplified vs 2D: the shrine rune puzzle is skipped (the altar wakes
-- the Stone Guardian directly), trails are not sealed during boss fights, and progress
-- is not saved yet. Rewards add XP/runes (port grind system).
-- TODO(port): shrine puzzle (puzzles.py), sealed encounters, chapter_flow (Dunmere chain).
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = require(Shared.Data)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.State)
local Progress = require(script.Parent.Progress)
local EnemyService = require(script.Parent.EnemyService)

local Adventure = Data.Adventure

local Dunmere = require(script.Parent.Dunmere)
local ShrinePuzzle = require(script.Parent.ShrinePuzzle)
local Opening = require(script.Parent.OpeningService)

local Quests = {}

local BOSSES = {
	shrine = { key = "shrine", name = "Shrine Stone Guardian", kind = "troll", hp = 250, damage = 8, speed = 48, scale = 1.7, xPx = 480, yPx = 205 },
	region = { key = "region", name = "Labyrinth Minotaur King", kind = "minotaur", hp = 540, damage = 11, speed = 75, scale = 1.9, xPx = 480, yPx = 205 },
}

local function pagesFor(key: string)
	local page = Adventure.PAGES["adventure_" .. key]
	return page[1], page[2]
end

local function say(player: Player, title: string, pages)
	Remotes.get("Dialogue"):FireClient(player, title, pages)
end

local function tell(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function party(fn)
	for _, player in Players:GetPlayers() do
		fn(player)
	end
end

-- Everyone gets the same quest reward.
local function reward(xp: number, runes: number, message: string)
	party(function(player)
		Progress.addXp(player, xp)
		Progress.addRunes(player, runes)
		tell(player, ("%s  +%d xp  +%d runes"):format(message, xp, runes))
	end)
end

local function giveGear(key: string, kind: string)
	party(function(player)
		local id
		if kind == "class_weapon" then
			id = Data.Items.classWeapons[State.heroes[player]]
		else
			id = Adventure.CLASS_REWARDS[State.heroes[player]]
		end
		if id and Progress.grant(player, id, State.heroes[player]) then
			tell(player, "New gear equipped: " .. Data.Items.items[id].name)
		end
	end)
end

function Quests.objective(): string
	if Opening.active() then
		return "The Last Caravan: hold the road against both attacks, then gather at the gold circle by the gate."
	end
	local q = State.quests
	local mark = function(v)
		return v == "done" and "[x]" or "[ ]"
	end
	local line
	if q.hunter == "new" then
		line = "Talk to the Village Runner in Oakvale."
	elseif q.hunter == "active" then
		line = "Find the missing hunter in the clearing (Southern road, then east)."
	elseif q.bridge ~= "done" then
		line = State.flags.kit and "Take the repair kit to the bridge workbench." or "Find repair supplies at the abandoned camp."
	elseif q.shrine ~= "done" then
		if State.flags.puzzle then
			line = "Rune puzzle: read your totem (E), then stand on the matching rune. In a party, share clues."
		else
			line = q.shrine == "active" and State.enemies["shrine-boss-shrine"] and "Defeat the Shrine Stone Guardian."
				or "Silence the overgrown shrine (south of the crossroads)."
		end
	elseif q.region ~= "done" then
		line = q.region == "active" and "Defeat the Labyrinth Minotaur King." or "Break the ruins gate seal."
	else
		local text = Dunmere.objective()
		if text then
			return text
		end
		line = "Woodland secured."
	end
	return ("%s\n%s Hunter  %s Bridge  %s Shrine  %s Ruins"):format(line, mark(q.hunter), mark(q.bridge), mark(q.shrine), mark(q.region))
end

-- Where the current objective is: feature key + label for the HUD compass.
function Quests.target(): (string?, string?, string?)
	if Opening.active() then
		return "muster", "Gold muster circle"
	end
	local q = State.quests
	if q.hunter == "new" then
		return "runner", "Village Runner"
	elseif q.hunter == "active" then
		return "hunter", "Missing hunter"
	elseif q.bridge ~= "done" then
		if State.flags.kit then
			return "repair", "Bridge workbench"
		end
		return "kit", "Repair supplies"
	elseif q.shrine ~= "done" then
		if State.flags.puzzle then
			return "totem", "Shrine totem"
		end
		return "altar", "Overgrown shrine"
	elseif q.region ~= "done" then
		return "seal", "Ruins gate seal"
	end
	return Dunmere.target()
end

function Quests.broadcast(player: Player?)
	local text = Quests.objective()
	local key, label, areaId = Quests.target()
	-- Oakvale-chain targets live in the home area first; keys such as "runner" also exist in Dunmere.
	local home = State.featurePosByArea.home
	local pos = key and ((home and home[key]) or State.featurePos[key]) or nil
	if not Quests._logged then
		Quests._logged = true
		print(("[Gauntlet] first objective target: %s (%s) at %s"):format(tostring(key), tostring(areaId), tostring(pos)))
	end
	if key == "muster" then
		pos = Opening.musterPos()
	end
	if key == "totem" then
		pos = ShrinePuzzle.totemPos()
	end
	if areaId then
		pos = Dunmere.position(key, areaId)
	end
	for _, marker in CollectionService:GetTagged("QuestMarker") do
		marker.Enabled = marker:GetAttribute("Key") == key and (not areaId or marker:FindFirstAncestor(areaId) ~= nil)
	end
	if player then
		Remotes.get("Objective"):FireClient(player, text)
		Remotes.get("Waypoint"):FireClient(player, pos, label)
	else
		Remotes.get("Objective"):FireAllClients(text)
		Remotes.get("Waypoint"):FireAllClients(pos, label)
	end
end

local function finish(key: string)
	State.quests[key] = "done"
	Quests.broadcast()
end

-- Returns true when the feature belonged to a quest and was handled.
function Quests.interact(player: Player, feature): boolean
	local q = State.quests
	local key, area = feature.key, feature.area

	if key == "runner" and area == "home" then
		if q.hunter == "new" then
			q.hunter = "active"
			Quests.broadcast()
		end
		local title, pages = pagesFor("welcome")
		say(player, title, pages)
		return true
	end

	if key == "hunter" then
		if q.hunter == "new" then
			tell(player, "Speak to the Village Runner in Oakvale first.")
		elseif q.hunter == "active" then
			local title, pages = pagesFor("hunter")
			say(player, title, pages)
			finish("hunter")
			reward(120, 25, "Missing hunter found!")
		else
			local title, pages = pagesFor("recovered")
			say(player, title, pages)
		end
		return true
	end

	if key == "kit" then
		if State.flags.kit then
			tell(player, "The chest is empty - you already took the repair kit.")
		else
			State.flags.kit = true
			local title, pages = pagesFor("kit")
			say(player, title, pages)
			reward(30, 15, "Repair supplies found!")
			Quests.broadcast()
		end
		return true
	end

	if key == "repair" then
		if q.bridge == "done" then
			local title, pages = pagesFor("repair")
			say(player, title, pages)
		elseif not State.flags.kit then
			tell(player, "You need repair supplies from the abandoned camp.")
		else
			local title, pages = pagesFor("repair")
			say(player, title, pages)
			finish("bridge")
			reward(100, 20, "Bridge restored!")
		end
		return true
	end

	if key == "altar" then
		if q.shrine == "done" then
			tell(player, "The shrine glows green. The poison is gone.")
		elseif q.shrine == "active" and State.enemies["shrine-boss-shrine"] then
			tell(player, "The Stone Guardian is awake. Defeat it!")
		elseif ShrinePuzzle.active() then
			tell(player, "Read the totem for a clue, then stand on the matching rune.")
		else
			local title, pages = pagesFor("shrine")
			say(player, title, pages)
			q.shrine = "active"
			ShrinePuzzle.start()
			Quests.broadcast()
		end
		return true
	end

	if key == "seal" then
		if q.region == "done" then
			tell(player, "The seal is broken. The Minotaur King is no more.")
		elseif q.hunter ~= "done" or q.bridge ~= "done" or q.shrine ~= "done" then
			tell(player, "The seal will not yield. Find the hunter, restore the bridge and silence the shrine first.")
		elseif q.region == "active" and State.enemies["ruins-boss-region"] then
			tell(player, "The Minotaur King is awake. Defeat it!")
		else
			q.region = "active"
			EnemyService.spawnBoss("ruins", BOSSES.region)
			Quests.broadcast()
			party(function(p)
				tell(p, "The Labyrinth Minotaur King awakens!")
			end)
		end
		return true
	end

	if Dunmere.interact(player, feature) then
		return true
	end

	return false
end

-- Hooked from EnemyService.onKill.
function Quests.onKill(enemy)
	if enemy.bossKey == "shrine" then
		finish("shrine")
		reward(200, 35, "The shrine is restored!")
		giveGear("shrine", "class_weapon")
	elseif enemy.bossKey == "region" then
		finish("region")
		reward(450, 70, "WOODLAND REGION COMPLETE!")
		giveGear("region", "class_reward")
		party(function(player)
			local title, pages = pagesFor("complete")
			say(player, title, pages)
		end)
	end
end

function Quests.start()
	ShrinePuzzle.onSolved = function()
		EnemyService.spawnBoss("shrine", BOSSES.shrine)
		Quests.broadcast()
	end
	Dunmere.start()
	Dunmere.onChange = function()
		Quests.broadcast()
	end
	EnemyService.onKill = function(enemy)
		Quests.onKill(enemy)
	end
	Players.PlayerAdded:Connect(function(player)
		task.delay(2, function()
			Quests.broadcast(player)
		end)
	end)
	for _, player in Players:GetPlayers() do
		Quests.broadcast(player)
	end
end

return Quests
