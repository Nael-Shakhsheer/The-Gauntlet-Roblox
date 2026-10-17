--!nonstrict
-- Skills v1 (port of hero_skills.py, compact). Milestone points (+ a few level points) are spent on
-- the hero's tree: abilities (starters free), ranked modifiers. Locked abilities cannot be cast.
-- Changes only in hubs (Oakvale / Dunmere). Hero change resets ranks. Ranks are saved in the profile.
-- v1 gaps: new-active nodes and passives show as "coming soon" (cannot be bought); no loadout limit.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Data = require(Shared.Data)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.State)
local Progress = require(script.Parent.Progress)

local Skills = {}

local MILESTONES = Data.HeroSkills.MILESTONES
local MILESTONE_ORDER = { "arrival", "road", "inn", "hunter", "bridge", "shrine", "alcove", "cave", "floor1", "floor2", "tower", "region" }
local ranks = {} -- [player] = { [nodeId] = rank }
local nodeCache = {} -- hero -> { [id] = node }
local abilityCache = {} -- [player] = { [slot] = record }
local supported -- forward decl, set below

local function tree(hero)
	return Data.HeroSkills.TREES[hero]
end

local function nodes(hero)
	local n = nodeCache[hero]
	if not n then
		n = {}
		for _, node in tree(hero) or {} do
			n[node.id] = node
		end
		nodeCache[hero] = n
	end
	return n
end

local baseIds = {} -- hero -> { [abilityId] = slot }
local function baseSlots(hero)
	local b = baseIds[hero]
	if not b then
		b = {}
		for slot, a in Data.Abilities.sets[hero] do
			b[a.id] = slot
		end
		baseIds[hero] = b
	end
	return b
end
function Skills.isBase(node, hero)
	return node.type == "ability" and hero ~= nil and baseSlots(hero)[node.id] ~= nil
end
supported = function(node, hero)
	return node.type == "modifier" or Skills.isBase(node, hero)
end

local function facts(): { [string]: boolean }
	local c = State.claimed
	return {
		arrival = true,
		road = State.discovered.road == true,
		inn = c.inn == true,
		hunter = State.quests.hunter == "done",
		bridge = State.quests.bridge == "done",
		shrine = State.quests.shrine == "done",
		alcove = c.cave_survey == true,
		cave = c["dg:cave"] == true,
		floor1 = c["dg:tower:f1"] == true,
		floor2 = c["dg:tower:f2"] == true,
		tower = c["dg:tower:f3"] == true,
		region = State.quests.region == "done",
	}
end

function Skills.earned(player: Player): number
	local total = 0
	local f = facts()
	for k, v in MILESTONES do
		if f[k] then
			total += v
		end
	end
	total += math.floor(Progress.get(player).level / Config.LEVEL_POINT_EVERY)
	return total
end

function Skills.spent(player: Player): number
	local hero = State.heroes[player]
	local n = nodes(hero)
	local total = 0
	for id, r in ranks[player] or {} do
		if n[id] then
			total += n[id].cost * r
		end
	end
	return total
end

function Skills.points(player: Player): number
	return Skills.earned(player) - Skills.spent(player)
end

function Skills.rank(player: Player, id: string): number
	return (ranks[player] and ranks[player][id]) or 0
end

function Skills.unlocked(player: Player, id: string): boolean
	local node = nodes(State.heroes[player])[id]
	if not node then
		return false
	end
	return node.starter == true or Skills.rank(player, id) > 0
end

-- the ability record for a hotbar slot with modifiers applied (cached until ranks change)
function Skills.ability(player: Player, hero: string, slot: number)
	local cache = abilityCache[player]
	if not cache or cache.hero ~= hero then
		cache = { hero = hero }
		abilityCache[player] = cache
	end
	local rec = cache[slot]
	if rec then
		return rec
	end
	local base = Data.Abilities.sets[hero][slot]
	rec = table.clone(base)
	for _, node in tree(hero) or {} do
		if node.type == "modifier" then
			local r = Skills.rank(player, node.id)
			if r > 0 then
				for _, req in node.requires do
					if req == base.id then
						for k, v in node.changes[r] do
							rec[k] = v
						end
					end
				end
			end
		end
	end
	cache[slot] = rec
	return rec
end

function Skills.slotUnlocked(player: Player, hero: string, slot: number): boolean
	local base = Data.Abilities.sets[hero][slot]
	return base ~= nil and Skills.unlocked(player, base.id)
end

local function hubName(player: Player): string?
	local area = State.playerArea[player]
	return area and Data.RegionContent.HUBS[area] or nil
end

local function describe(player: Player)
	local hero = State.heroes[player]
	local f = facts()
	local milestones = {}
	for _, k in MILESTONE_ORDER do
		table.insert(milestones, { id = k, points = MILESTONES[k], earned = f[k] == true })
	end
	local owned, unlocked = {}, {}
	for id, r in ranks[player] or {} do
		owned[id] = r
	end
	for _, node in tree(hero) or {} do
		if Skills.unlocked(player, node.id) then
			unlocked[node.id] = true
		end
	end
	return {
		hero = hero,
		points = Skills.points(player),
		earned = Skills.earned(player),
		ranks = owned,
		unlocked = unlocked,
		hub = hubName(player),
		milestones = milestones,
	}
end

function Skills.push(player: Player)
	if player.Parent and State.heroes[player] then
		Remotes.get("SkillsState"):FireClient(player, describe(player))
	end
end

local function notify(player: Player, msg: string)
	Remotes.get("Notify"):FireClient(player, msg)
end

local function unlock(player: Player, id)
	local hero = State.heroes[player]
	local node = type(id) == "string" and nodes(hero)[id]
	if not node then
		return
	end
	if node.starter or Skills.rank(player, id) >= node.maxRank then
		notify(player, "Already fully unlocked.")
		return
	end
	if not supported(node, hero) then
		notify(player, node.name .. " arrives in a later update.")
		return
	end
	for _, req in node.requires do
		if not Skills.unlocked(player, req) then
			local pre = nodes(hero)[req]
			notify(player, "Unlock " .. (pre and pre.name or "the prerequisite") .. " first.")
			return
		end
	end
	if Skills.points(player) < node.cost then
		notify(player, "Not enough skill points.")
		return
	end
	ranks[player] = ranks[player] or {}
	ranks[player][id] = Skills.rank(player, id) + 1
	abilityCache[player] = nil
	notify(player, node.name .. " trained.")
end

local function respec(player: Player)
	ranks[player] = {}
	abilityCache[player] = nil
	notify(player, "Skills reset. Points refunded.")
end

local function request(player: Player, action, id)
	if not State.heroes[player] then
		return
	end
	if action == "unlock" or action == "respec" then
		if not hubName(player) then
			notify(player, "Change skills in Oakvale or Dunmere.")
			return
		end
		if action == "unlock" then
			unlock(player, id)
		else
			respec(player)
		end
	end
	Skills.push(player)
end

-- ------------------------------------------------------------- persistence

function Skills.snapshot(player: Player)
	return { hero = State.heroes[player], ranks = ranks[player] or {} }
end

-- Validated restore; any inconsistency (unknown id, bad rank, overspend, broken prerequisite) drops all ranks.
function Skills.restore(player: Player, saved)
	ranks[player] = {}
	abilityCache[player] = nil
	local hero = State.heroes[player]
	if type(saved) ~= "table" or saved.hero ~= hero or type(saved.ranks) ~= "table" then
		return
	end
	local n = nodes(hero)
	local clean, spent = {}, 0
	for id, r in saved.ranks do
		local node = n[id]
		if not node or type(r) ~= "number" or r % 1 ~= 0 or r < 1 or r > node.maxRank or node.starter or not supported(node, hero) then
			return
		end
		clean[id] = r
		spent += node.cost * r
	end
	for id in clean do
		for _, req in n[id].requires do
			if not (n[req] and (n[req].starter or clean[req])) then
				return
			end
		end
	end
	ranks[player] = clean
	-- overspend can happen if the world (milestone) state is behind; keep ranks, points just show negative until caught up
	Skills.push(player)
end

function Skills.onHeroChange(player: Player)
	ranks[player] = {}
	abilityCache[player] = nil
	Skills.push(player)
end

function Skills.start()
	Remotes.get("Skills").OnServerEvent:Connect(request)
	Players.PlayerRemoving:Connect(function(player)
		ranks[player] = nil
		abilityCache[player] = nil
	end)
	-- points change with level / quests / dungeons: refresh clients periodically (cheap)
	task.spawn(function()
		while true do
			task.wait(3)
			for _, player in Players:GetPlayers() do
				Skills.push(player)
			end
		end
	end)
end

return Skills
