--!nonstrict
-- One place that creates / looks up every RemoteEvent, by name.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"SelectHero", -- client -> server: hero name
	"Cast", -- client -> server: ability index 1-6 (2 Lights, 2 Specials, 2 Ultimates)
	"Vitals", -- server -> client: mana, maxMana, cooldown seconds left by index, summonAlive by index
	"Dialogue", -- server -> client: title, pages
	"AreaChanged", -- server -> client: area id, display name, region
	"Notify", -- server -> client: short message
	"EnemyHit", -- server -> client: world position, damage
	"HeroChanged", -- server -> client: hero name
	"Reward", -- server -> client: xp, runes, world position of a kill
	"ShopOpen", -- server -> client: stock list, runes, level
	"Buy", -- client -> server: item id
	"TravelOpen", -- server -> client: list of waystones {id,name,active,here}
	"Travel", -- client -> server: waystone id
	"Objective", -- server -> client: quest tracker text
	"UseItem", -- client -> server: potion id from the pouch
	"GuildOpen", -- server -> client: open the hero registry (Guild board)
	"Bounty", -- server -> client: guild bounty progress line ("" = none)
	"Waypoint", -- server -> client: world position of the current objective (or nil), label
	"Sprint", -- client -> server: bool, holding sprint
	"Dodge", -- client -> server: unit direction; server -> clients: userId, position, direction
	"Skills", -- client -> server: action ("unlock"/"respec"), node id
	"SkillsState", -- server -> client: points, ranks, unlocked, hub, milestones
	"Inventory", -- server -> client: equipped gear, bag, runes; client -> server: action, arg
	"LootDrop", -- server -> client: drop id, position, gear instance
	"LootTaken", -- server -> client: drop id
	"AbilityFx", -- server -> all clients: ability visual payload (see client/AbilityFx.luau)
}

local Remotes = {}

local function folder(): Folder
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		return existing
	end
	if RunService:IsServer() then
		local created = Instance.new("Folder")
		created.Name = "Remotes"
		created.Parent = ReplicatedStorage
		return created
	end
	return ReplicatedStorage:WaitForChild("Remotes")
end

function Remotes.init() -- call once from the server before anything else
	assert(RunService:IsServer(), "Remotes.init is server-only")
	local f = folder()
	for _, name in NAMES do
		if not f:FindFirstChild(name) then
			local event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = f
		end
	end
end

function Remotes.get(name: string): RemoteEvent
	return folder():WaitForChild(name)
end

return Remotes
