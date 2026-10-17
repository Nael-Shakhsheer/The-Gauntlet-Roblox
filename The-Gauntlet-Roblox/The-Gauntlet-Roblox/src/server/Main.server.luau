--!nonstrict
-- Boot order matters: remotes -> world -> heroes -> combat -> enemy AI.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

Remotes.init()

-- Dev convenience: the default template's Baseplate/SpawnLocation sit under our areas.
for _, name in { "Baseplate", "SpawnLocation" } do
	local leftover = Workspace:FindFirstChild(name)
	if leftover then
		leftover:Destroy()
	end
end

local WorldService = require(script.Parent.WorldService)
local HeroService = require(script.Parent.HeroService)
local CombatService = require(script.Parent.CombatService)
local EnemyService = require(script.Parent.EnemyService)
local Companions = require(script.Parent.Companions)
local Quests = require(script.Parent.Quests)
local Interactions = require(script.Parent.Interactions)
local Services = require(script.Parent.Services)
local DungeonService = require(script.Parent.DungeonService)
local Opening = require(script.Parent.OpeningService)
local Fallen = require(script.Parent.Fallen)
local Persistence = require(script.Parent.Persistence)

-- One failing module must not take the whole server down: each start is guarded and named in the log.
local function boot(name: string, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		warn(("[Gauntlet] %s failed to start:\n%s"):format(name, tostring(err)))
	end
end

-- Cheap request handlers first: the world build below can take a while and the client UI
-- (Skills, Bag) must already be answered while it runs.
boot("Skills", function()
	require(script.Parent.Skills).start()
end)
boot("Loot", function()
	require(script.Parent.Loot).start()
end)

boot("WorldService", WorldService.start)
boot("HeroService", function()
	HeroService.start(WorldService.spawnPlayer)
end)
boot("CombatService", CombatService.start)
boot("EnemyService", EnemyService.start)
boot("Companions", Companions.start)
boot("Quests", Quests.start)
boot("Interactions", Interactions.start)
boot("Services", Services.start) -- after Quests.start: chains EnemyService.onKill
boot("Opening", Opening.start)
boot("DungeonService", DungeonService.start) -- after Services (chains onKill)
boot("Persistence", Persistence.start) -- before Fallen so loads begin before the first spawn waits on them
boot("Fallen", Fallen.start) -- last: turns on manual character loading after HeroService hooked CharacterAdded

print(("[Gauntlet] connected Adventure world ready, up to %d players"):format(Config.MAX_PLAYERS))
