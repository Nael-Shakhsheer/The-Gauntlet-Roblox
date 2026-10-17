--!nonstrict
-- DataStore saves for the grind: level, xp, runes, weapon, armour and chosen hero.
-- Per player (key "p_<UserId>"). Each profile also carries a copy of the world progress (quests,
-- attuned shrines, discovered areas, opened chests, kit flag). On join it is MERGED into the server's
-- state (furthest quest step wins, sets are unioned), so a party keeps its progress as long as anyone
-- who played with it returns. Bosses/enemies are not saved. If a load fails (e.g. Studio API access off) saving is disabled for
-- that session so a bad load can never overwrite real data.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Data = require(Shared.Data)
local Gear = require(Shared.Gear)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.State)
local Progress = require(script.Parent.Progress)

local STORE_NAME = "GauntletProfiles_v1"
local AUTOSAVE_SECONDS = 60
local VERSION = 1

local Persistence = {}
local store
local loaded = {} -- [player] = true once load finished (success or not)
local canSave = {} -- [player] = true if the load succeeded
local saving = {}

local function key(player: Player)
	return "p_" .. player.UserId
end

local function attempt(fn, tries: number)
	local ok, result
	for i = 1, tries do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		task.wait(1.5 * i)
	end
	return false, result
end

local function sanitize(saved)
	if type(saved) ~= "table" then
		return nil
	end
	local function gear(raw, slot)
		local inst = Gear.valid(raw)
		return inst and Gear.slotOf(inst) == slot and inst or nil
	end
	local bag = {}
	if type(saved.bag) == "table" then
		for i = 1, math.min(#saved.bag, Progress.BAG_SIZE) do
			local inst = Gear.valid(saved.bag[i])
			if inst then
				table.insert(bag, inst)
			end
		end
	end
	local level = math.clamp(math.floor(tonumber(saved.level) or 1), 1, Config.MAX_LEVEL)
	local function keySet(source, validate)
		local out = {}
		if type(source) == "table" then
			local n = 0
			for k, v in source do
				if v == true and type(k) == "string" and #k <= 64 and n < 500 and (not validate or validate(k)) then
					out[k] = true
					n += 1
				end
			end
		end
		return out
	end
	local world = type(saved.world) == "table" and saved.world or {}
	local quests = {}
	if type(world.quests) == "table" then
		for _, key in { "hunter", "bridge", "shrine", "region", "failed_harvest", "irrigation", "mill_cellar", "outcome" } do
			local v = world.quests[key]
			if v == "new" or v == "active" or v == "done" then
				quests[key] = v
			end
		end
	end
	return {
		world = {
			quests = quests,
			kit = world.kit == true,
			attuned = keySet(world.attuned),
			discovered = keySet(world.discovered, function(k)
				return Data.Adventure.AREAS[k] ~= nil
			end),
			claimed = keySet(world.claimed),
		},
		level = level,
		xp = level >= Config.MAX_LEVEL and 0 or math.max(0, math.floor(tonumber(saved.xp) or 0)),
		runes = math.max(0, math.floor(tonumber(saved.runes) or 0)),
		weapon = gear(saved.weapon, "w"),
		armor = gear(saved.armor, "a"),
		trinket = gear(saved.trinket, "t"),
		bag = bag,
		hero = type(saved.hero) == "string" and Data.Heroes[saved.hero] and saved.hero or nil,
		skills = saved.skills, -- validated by Skills.restore
		pouch = (function()
			local out = {}
			if type(saved.pouch) == "table" then
				for _, id in Progress.POTION_ORDER do
					local n = math.floor(tonumber(saved.pouch[id]) or 0)
					if n > 0 then
						out[id] = math.min(n, Progress.POTION_MAX)
					end
				end
			end
			return out
		end)(),
	}
end

local function snapshot(player: Player)
	local p = Progress.get(player)
	return {
		v = VERSION,
		level = p.level,
		xp = p.xp,
		runes = p.runes,
		weapon = p.weapon,
		armor = p.armor,
		trinket = p.trinket,
		bag = p.bag,
		hero = State.heroes[player],
		pouch = p.pouch,
		skills = require(script.Parent.Skills).snapshot(player),
		world = {
			quests = State.quests,
			kit = State.flags.kit == true,
			attuned = State.attuned,
			discovered = State.discovered,
			claimed = State.claimed,
		},
	}
end

local RANK = { new = 0, active = 1, done = 2 }
local function mergeWorld(world)
	for key, value in world.quests do
		if (RANK[value] or 0) > (RANK[State.quests[key]] or 0) then
			State.quests[key] = value
		end
	end
	if world.kit then
		State.flags.kit = true
	end
	for _, name in { "attuned", "discovered", "claimed" } do
		for k in world[name] do
			State[name][k] = true
		end
	end
end

function Persistence.save(player: Player, data)
	if not store or not canSave[player] or saving[player] then
		return
	end
	saving[player] = true
	data = data or snapshot(player)
	local ok, err = attempt(function()
		store:SetAsync(key(player), data)
	end, 3)
	if not ok then
		warn(("[Gauntlet] save failed for %s: %s"):format(player.Name, tostring(err)))
	end
	saving[player] = nil
end

local function load(player: Player)
	if store then
		local ok, result = attempt(function()
			return store:GetAsync(key(player))
		end, 3)
		if ok then
			canSave[player] = true
			local data = sanitize(result)
			if data and player.Parent then
				local p = Progress.get(player)
				p.level, p.xp, p.runes, p.weapon, p.armor, p.pouch = data.level, data.xp, data.runes, data.weapon, data.armor, data.pouch
				p.trinket, p.bag = data.trinket, data.bag
				Progress.invalidate(player)
				if data.hero then
					State.heroes[player] = data.hero
					State.heroChosen[player] = true
					player:SetAttribute("HeroLocked", true)
					Remotes.get("HeroChanged"):FireClient(player, data.hero)
				end
				Progress.sync(player)
				mergeWorld(data.world)
				require(script.Parent.Skills).restore(player, data.skills)
				require(script.Parent.DungeonService).refresh()
				require(script.Parent.Quests).broadcast()
				Remotes.get("Notify"):FireClient(player, ("Progress loaded: level %d."):format(data.level))
			end
		else
			warn(("[Gauntlet] load failed for %s (saving disabled this session): %s"):format(player.Name, tostring(result)))
			Remotes.get("Notify"):FireClient(player, "Could not load saved progress; this session will not be saved.")
		end
	end
	loaded[player] = true
end

-- Spawning waits for this so the first character gets its saved level/hero.
function Persistence.waitLoaded(player: Player)
	local waited = 0
	while not loaded[player] and player.Parent and waited < 20 do
		task.wait(0.1)
		waited += 0.1
	end
end

function Persistence.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	store = ok and result or nil
	if not store then
		warn("[Gauntlet] DataStore unavailable; progress will not be saved.")
	end

	-- Final snapshot is taken before HeroService clears the player's state.
	Progress.onDrop = function(player)
		local data = snapshot(player)
		loaded[player] = nil
		task.spawn(function()
			Persistence.save(player, data)
			canSave[player] = nil
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for _, player in Players:GetPlayers() do
				if loaded[player] then
					task.spawn(Persistence.save, player)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for _, player in Players:GetPlayers() do
			if loaded[player] and canSave[player] then
				pending += 1
				local data = snapshot(player)
				task.spawn(function()
					saving[player] = nil
					Persistence.save(player, data)
					pending -= 1
				end)
			end
		end
		local t = 0
		while pending > 0 and t < 25 do
			task.wait(0.2)
			t += 0.2
		end
	end)
end

return Persistence
