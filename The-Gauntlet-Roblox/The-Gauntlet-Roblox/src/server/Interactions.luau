--!nonstrict
-- E-key interactions: quest features (Quests), shop, inn beds, waystones/travel, one-time
-- chests and discoveries, and plain dialogue from the 2D text tables.
-- Village services (innkeeper, alchemist, guild, cottage...) live in Services.luau.
-- TODO(port): dungeon mechanisms, shrine/ruin puzzles, soul crystal.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = require(Shared.Data)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.State)
local Progress = require(script.Parent.Progress)
local Quests = require(script.Parent.Quests)
local EnemyService = require(script.Parent.EnemyService)
local Services = require(script.Parent.Services)

local Adventure = Data.Adventure
local RegionContent = Data.RegionContent

local DungeonService = require(script.Parent.DungeonService)

local Interactions = {}

local TRAVEL_REACH = 28 -- studs from the waystone you opened
local ENEMY_BLOCK = 40 -- studs: no travelling with enemies this close

local function tell(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

-- Messages from the 2D game's dialogue tables: PAGES (title + pages) first,
-- then region text, then a placeholder for content not ported yet.
function Interactions.dialogueFor(feature)
	local page = Adventure.PAGES["adventure_" .. feature.key]
	if page then
		return page[1], page[2]
	end
	local text = RegionContent.TEXT[feature.key]
	if text then
		return feature.name, { text }
	end
	return feature.name, { "(This interaction has not been ported from the 2D game yet.)" }
end

local function say(player: Player, feature)
	local title, pages = Interactions.dialogueFor(feature)
	Remotes.get("Dialogue"):FireClient(player, title, pages)
end

-- ------------------------------------------------------------- waystones

local function waystoneActive(way): boolean
	if way.shrine then
		return State.attuned[way.shrine] == true
	end
	return State.discovered[way.area] == true
end

local function waystoneList(player: Player, here: string?)
	local list = {}
	for id, way in State.waystones do
		table.insert(list, {
			id = id,
			name = way.name,
			active = waystoneActive(way),
			here = id == here,
			level = Progress.requiredLevel(way.area),
		})
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

local function openTravel(player: Player, feature)
	local way = State.waystones[feature.key]
	State.waystoneAt[player] = feature.key
	if way and waystoneActive(way) then
		local previous = State.respawn[player]
		State.respawn[player] = way.pos + Vector3.new(4, 0, 4)
		if not previous or (previous - way.pos).Magnitude > 30 then
			tell(player, "Waystone bound: you will return here if you fall.")
		end
	end
	Remotes.get("TravelOpen"):FireClient(player, waystoneList(player, feature.key), way and way.name or feature.name)
end

local function attune(player: Player, feature): boolean
	local spec = RegionContent.SHRINES[feature.shrine]
	if State.attuned[feature.shrine] then
		return true
	end
	if not EnemyService.groupCleared(spec.area, spec.guards) then
		tell(player, "Defeat the shrine's guards before attuning it. (" .. spec.description .. ")")
		return false
	end
	State.attuned[feature.shrine] = true
	for _, p in Players:GetPlayers() do
		tell(p, spec.name .. " attuned! You can now travel here from any waystone.")
	end
	return true
end

function Interactions.travel(player: Player, destinationId)
	local fromId = State.waystoneAt[player]
	local from = fromId and State.waystones[fromId]
	local to = typeof(destinationId) == "string" and State.waystones[destinationId]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (from and to and root and humanoid and humanoid.Health > 0) then
		return
	end
	if (root.Position - from.pos).Magnitude > TRAVEL_REACH then
		tell(player, "Stand next to the waystone to travel.")
		return
	end
	if not waystoneActive(to) then
		tell(player, "That waystone is not active yet.")
		return
	end
	if destinationId == fromId then
		return
	end
	local need = Progress.requiredLevel(to.area)
	if Progress.get(player).level < need then
		tell(player, ("%s requires level %d."):format(to.name, need))
		return
	end
	for _, e in State.enemies do
		if (e.model.PrimaryPart.Position - root.Position).Magnitude < ENEMY_BLOCK then
			tell(player, "Enemies are too close. Retreat before travelling.")
			return
		end
	end
	character:PivotTo(CFrame.new(to.pos + Vector3.new(0, 4, 8)))
	State.waystoneAt[player] = nil
	tell(player, "Arrived at " .. to.name .. ".")
end

-- ------------------------------------------------------------------ shop

local function openShop(player: Player, feature)
	State.shopMode[player] = "gear"
	local hero = State.heroes[player]
	Remotes.get("ShopOpen"):FireClient(player, Progress.stock(player, hero), feature.name)
end

function Interactions.buy(player: Player, id)
	if typeof(id) ~= "string" then
		return
	end
	local ok, message
	if Progress.isPotion(id) then
		ok, message = Progress.buyPotion(player, id)
	else
		ok, message = Progress.buy(player, State.heroes[player], id)
	end
	tell(player, message)
	if ok then
		Services.refreshShop(player, State.heroes[player])
	end
end

-- ------------------------------------------------------------------- inn

local function rest(player: Player, feature)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then
		return
	end
	humanoid.Health = humanoid.MaxHealth
	require(script.Parent.Stats).get(player).mana = 100
	State.respawn[player] = root.Position
	tell(player, "You rest. Health and mana restored; you will return here if you fall.")
end

-- ---------------------------------------------------------------- chests

local function claim(player: Player, feature)
	if State.claimed[feature.key] then
		tell(player, "Already looted.")
		return
	end
	State.claimed[feature.key] = true
	local danger = Adventure.AREAS[feature.area].danger
	local discovery = Adventure.DISCOVERIES[feature.key]
	local runes = discovery and discovery.runes or (8 + danger * 4)
	for _, p in Players:GetPlayers() do
		Progress.addRunes(p, runes)
		Progress.addXp(p, 10 + danger * 6)
		tell(p, ("Found %d runes!"):format(runes))
	end
	say(player, feature)
end

-- ------------------------------------------------------------- dispatch

function Interactions.handle(player: Player, feature)
	if Quests.interact(player, feature) then
		return
	end
	if feature.service == "merchant" then
		openShop(player, feature)
		return
	elseif Services.handle(player, feature) or DungeonService.handle(player, feature) then
		return
	end
	local kind = feature.kind
	if kind == "shop" then
		openShop(player, feature)
	elseif kind == "inn" then
		rest(player, feature)
	elseif kind == "waystone" then
		State.discovered[feature.area] = true
		openTravel(player, feature)
	elseif kind == "travel_shrine" then
		if attune(player, feature) then
			openTravel(player, feature)
		end
	elseif kind == "chest" or kind == "dungeon_treasure" or kind == "discovery" then
		claim(player, feature)
	else
		say(player, feature)
	end
end

function Interactions.start()
	Remotes.get("Buy").OnServerEvent:Connect(Interactions.buy)
	Remotes.get("Travel").OnServerEvent:Connect(Interactions.travel)
	Players.PlayerRemoving:Connect(function(player)
		State.waystoneAt[player] = nil
		State.respawn[player] = nil
	end)
end

return Interactions
