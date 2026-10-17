--!nonstrict
-- Blocky enemy bodies for the five outdoor families. Each model has an
-- anchored PrimaryPart ("Root") that EnemyService moves with PivotTo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Make = require(ReplicatedStorage:WaitForChild("Shared").Make)
local Rig = require(ReplicatedStorage:WaitForChild("Shared").Rig)

local EnemyModels = {}

local function box(model, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?, name: string?)
	return Make.part({
		Name = name or "Part",
		Size = size,
		CFrame = CFrame.new(offset),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = false,
	}, model)
end

-- Every part is created at the origin; the model is positioned afterwards.
local BUILDERS = {}

function BUILDERS.wolf(model, color, accent)
	local root = box(model, Vector3.new(1.6, 1.8, 4), Vector3.new(0, 2.2, 0), color)
	box(model, Vector3.new(1.4, 1.4, 1.8), Vector3.new(0, 2.8, -2.6), color, nil, "Head")
	box(model, Vector3.new(0.8, 0.7, 1.1), Vector3.new(0, 2.5, -3.9), Make.shade(color, -0.1))
	box(model, Vector3.new(0.4, 0.7, 0.4), Vector3.new(-0.5, 3.8, -2.6), Make.shade(color, -0.15))
	box(model, Vector3.new(0.4, 0.7, 0.4), Vector3.new(0.5, 3.8, -2.6), Make.shade(color, -0.15))
	box(model, Vector3.new(0.5, 0.5, 1.8), Vector3.new(0, 2.8, 2.7), accent, Enum.Material.Neon)
	for _, x in { -0.55, 0.55 } do
		for _, z in { -1.4, 1.4 } do
			box(model, Vector3.new(0.5, 1.4, 0.5), Vector3.new(x, 0.7, z), Make.shade(color, -0.12), nil, ((x > 0) == (z > 0)) and "Leg_A" or "Leg_B")
		end
	end
	box(model, Vector3.new(0.3, 0.3, 0.1), Vector3.new(-0.35, 3, -3.5), accent, Enum.Material.Neon)
	box(model, Vector3.new(0.3, 0.3, 0.1), Vector3.new(0.35, 3, -3.5), accent, Enum.Material.Neon)
	return root
end

function BUILDERS.spider(model, color, accent)
	local root = box(model, Vector3.new(2.6, 1.6, 3), Vector3.new(0, 1.8, 0.6), color)
	box(model, Vector3.new(1.6, 1.2, 1.4), Vector3.new(0, 1.9, -1.5), Make.shade(color, -0.08))
	for i, z in { -0.4, 0.4, 1.2, 2 } do
		for _, sign in { -1, 1 } do
			box(model, Vector3.new(2.6, 0.35, 0.35), Vector3.new(sign * 2, 1.2, z - 0.2 + i * 0.05), Make.shade(color, -0.14), nil, ((i + (sign > 0 and 1 or 0)) % 2 == 0) and "Leg_A" or "Leg_B")
		end
	end
	for _, x in { -0.4, 0.4 } do
		box(model, Vector3.new(0.3, 0.3, 0.1), Vector3.new(x, 2.1, -2.2), accent, Enum.Material.Neon)
	end
	return root
end

function BUILDERS.humanoid(model, color, accent, scale: number, extra)
	local s = scale
	box(model, Vector3.new(0.9 * s, 2.4 * s, 1 * s), Vector3.new(-0.55 * s, 1.2 * s, 0), Make.shade(color, -0.15), nil, "Leg_A")
	box(model, Vector3.new(0.9 * s, 2.4 * s, 1 * s), Vector3.new(0.55 * s, 1.2 * s, 0), Make.shade(color, -0.15), nil, "Leg_B")
	local root = box(model, Vector3.new(2.4 * s, 2.6 * s, 1.4 * s), Vector3.new(0, 3.7 * s, 0), color)
	box(model, Vector3.new(0.8 * s, 2.4 * s, 0.8 * s), Vector3.new(-1.6 * s, 3.7 * s, 0), Make.shade(color, -0.05), nil, "Arm_B")
	box(model, Vector3.new(0.8 * s, 2.4 * s, 0.8 * s), Vector3.new(1.6 * s, 3.7 * s, 0), Make.shade(color, -0.05), nil, "Arm_A")
	box(model, Vector3.new(1.7 * s, 1.7 * s, 1.7 * s), Vector3.new(0, 6 * s, 0), Make.shade(color, 0.08), nil, "Head")
	box(model, Vector3.new(0.35 * s, 0.35 * s, 0.1 * s), Vector3.new(-0.4 * s, 6.2 * s, -0.9 * s), accent, Enum.Material.Neon)
	box(model, Vector3.new(0.35 * s, 0.35 * s, 0.1 * s), Vector3.new(0.4 * s, 6.2 * s, -0.9 * s), accent, Enum.Material.Neon)
	if extra then
		extra(model, s, color, accent)
	end
	return root
end

function BUILDERS.serpent(model, color, accent)
	return BUILDERS.humanoid(model, color, accent, 1, function(m, s, c)
		box(m, Vector3.new(0.3, 7 * s, 0.3), Vector3.new(2.2 * s, 4 * s, -1 * s), Color3.fromRGB(120, 100, 66))
		box(m, Vector3.new(0.8, 1.2, 0.3), Vector3.new(2.2 * s, 7.8 * s, -1 * s), Color3.fromRGB(200, 200, 190))
	end)
end

function BUILDERS.troll(model, color, accent)
	return BUILDERS.humanoid(model, color, accent, 1.5, function(m, s, c)
		box(m, Vector3.new(1.6 * s, 1.1 * s, 1.6 * s), Vector3.new(0, 4.9 * s, -0.2 * s), Make.shade(c, -0.1)) -- hunched shoulders
	end)
end

function BUILDERS.minotaur(model, color, accent)
	return BUILDERS.humanoid(model, color, accent, 1.3, function(m, s, c)
		box(m, Vector3.new(0.4 * s, 1.2 * s, 0.4 * s), Vector3.new(-1 * s, 7.2 * s, 0), Color3.fromRGB(230, 220, 200))
		box(m, Vector3.new(0.4 * s, 1.2 * s, 0.4 * s), Vector3.new(1 * s, 7.2 * s, 0), Color3.fromRGB(230, 220, 200))
	end)
end

-- Returns Model with PrimaryPart set, bottom of feet at Y = 0.
function EnemyModels.build(kind: string, color: Color3, accent: Color3): Model
	local model = Instance.new("Model")
	local builder = BUILDERS[kind] or BUILDERS.troll
	local root = builder(model, color, accent)
	root.Name = "Root"
	model.PrimaryPart = root
	Rig.weld(model, root)
	return model
end

return EnemyModels
