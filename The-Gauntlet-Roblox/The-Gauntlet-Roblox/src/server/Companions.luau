--!nonstrict
-- Druid summons (Lightning Bird, Fire Wolf, Ice Bear, Nature Rock Golem): a companion
-- follows the owner and attacks the nearest enemy. 2D rule kept: the ability is locked
-- while its companion lives and recharges (summons[id].recharge) after it dies.
-- Port simplification: companions are not targeted by enemies; they expire after
-- LIFETIME seconds (or with their owner) so the recharge loop still exists.
-- TODO(port): companion hp / enemy aggro on companions (companion_ai.py).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Coord = require(Shared.Coord)
local Data = require(Shared.Data)
local Make = require(Shared.Make)

local State = require(script.Parent.State)
local EnemyModels = require(script.Parent.EnemyModels)
local EnemyService = require(script.Parent.EnemyService)

local Companions = {}

local LIFETIME = 25
local MODEL = { wolf = "wolf", bear = "troll", golem = "minotaur" }
local COLORS = {
	Storm = Color3.fromRGB(150, 200, 255),
	Fire = Color3.fromRGB(240, 120, 60),
	Ice = Color3.fromRGB(170, 220, 245),
	Nature = Color3.fromRGB(120, 160, 90),
}

local function bird(color: Color3): Model
	local model = Instance.new("Model")
	local root = Make.part({ Name = "Root", Size = Vector3.new(1.2, 1.2, 2), Color = color, Material = Enum.Material.Neon }, model)
	for _, side in { -1, 1 } do
		Make.part({ Size = Vector3.new(2.4, 0.2, 1.2), CFrame = root.CFrame * CFrame.new(side * 1.7, 0.2, 0) * CFrame.Angles(0, 0, side * 0.3), Color = color, Material = Enum.Material.Neon }, model)
	end
	model.PrimaryPart = root
	return model
end

local function build(info): Model
	local color = COLORS[info.affinity] or COLORS.Nature
	local model
	if info.kind == "bird" then
		model = bird(color)
	else
		model = EnemyModels.build(MODEL[info.kind] or "wolf", color, color)
	end
	model.Name = info.name
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
		end
	end
	return model
end

function Companions.alive(player: Player, abilityId: string): boolean
	return State.companions[player] ~= nil and State.companions[player][abilityId] ~= nil
end

local function retire(player: Player, abilityId: string, slot: number?)
	local list = State.companions[player]
	local c = list and list[abilityId]
	if not c then
		return
	end
	list[abilityId] = nil
	if c.model.Parent then
		c.model:Destroy()
	end
	if slot and State.cooldowns[player] then
		State.cooldowns[player][slot] = os.clock() + c.info.recharge
	end
end

-- damage: damage per hit (already 90%/200% of the light hit).
function Companions.summon(player: Player, abilityId: string, slot: number, damage: number)
	local info = Data.Abilities.summons[abilityId]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not info or not root then
		return false
	end
	local model = build(info)
	local offsetY = model.PrimaryPart.Position.Y + (info.kind == "bird" and 8 or 0)
	model:PivotTo(CFrame.new(root.Position + Vector3.new(4, offsetY - 3, 4)))
	model.Parent = workspace:FindFirstChild("Enemies") or workspace
	State.companions[player] = State.companions[player] or {}
	State.companions[player][abilityId] = {
		model = model,
		info = info,
		slot = slot,
		damage = damage,
		expires = os.clock() + LIFETIME,
		nextAttack = 0,
		offsetY = offsetY,
	}
	return true
end

local function tick(dt: number)
	local now = os.clock()
	for player, list in State.companions do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		for abilityId, c in list do
			if not root or not humanoid or humanoid.Health <= 0 or now >= c.expires or not c.model.Parent then
				retire(player, abilityId, c.slot)
				continue
			end
			local model = c.model
			local pos = model:GetPivot().Position
			local floorY = root.Position.Y - 3 + c.offsetY
			local target = EnemyService.nearestTo(root.Position, 34)
			local goal, stop = root.Position, 7
			if target then
				goal = target.model.PrimaryPart.Position
				stop = math.max(Coord.studs(c.info.range) * 0.8, 3)
			end
			local delta = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
			local dist = delta.Magnitude
			local speed = c.info.speed * 0.125
			if dist > stop then
				local step = math.min(dist - stop, speed * dt)
				pos += delta.Unit * step
			end
			local look = dist > 0.1 and Vector3.new(pos.X + delta.X, floorY, pos.Z + delta.Z) or nil
			local at = Vector3.new(pos.X, floorY, pos.Z)
			model:PivotTo(look and CFrame.lookAt(at, look) or CFrame.new(at))
			if target and dist <= stop + 1 and now >= c.nextAttack then
				c.nextAttack = now + c.info.attackInterval
				EnemyService.damage(target, c.damage, player, { dot = true })
			end
		end
	end
end

function Companions.start()
	RunService.Heartbeat:Connect(tick)
	Players.PlayerRemoving:Connect(function(player)
		for abilityId in State.companions[player] or {} do
			retire(player, abilityId, nil)
		end
		State.companions[player] = nil
	end)
end

return Companions
