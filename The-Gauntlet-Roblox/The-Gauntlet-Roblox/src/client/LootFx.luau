--!nonstrict
-- Ground loot visuals. Drops are personal: the server only tells *this* client about its own drops,
-- and picks them up by proximity. Here we just draw them (glow, light beam by rarity, floating name, magnet pull).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gear = require(Shared.Gear)
local Remotes = require(Shared.Remotes)
local Kit = require(script.Parent.Kit)

local LootFx = {}

local player = Players.LocalPlayer
local folder = Instance.new("Folder")
folder.Name = "LootFx"
folder.Parent = workspace

local drops = {} -- [id] = { part, beam, base: Vector3, t0, magnet }

local SHAPE = { w = Vector3.new(0.5, 2.2, 0.5), a = Vector3.new(1.5, 1.7, 0.6), t = Vector3.new(0.9, 0.9, 0.9) }

local function groundAt(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { folder }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 25, 0), Vector3.new(0, -60, 0), params)
	return hit and hit.Position or position
end

local function spawn(id: number, position: Vector3, inst)
	local info = Gear.describe(inst)
	if not info then
		return
	end
	local color = Color3.fromRGB(info.color[1], info.color[2], info.color[3])
	local rarity = info.rarityIndex
	local ground = groundAt(position)

	local part = Instance.new("Part")
	part.Name = "Loot"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = SHAPE[info.slotKey] or SHAPE.t
	part.CFrame = CFrame.new(ground + Vector3.new(0, 1.8, 0))
	part.Parent = folder

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 6 + rarity * 2
	light.Brightness = 0.8 + rarity * 0.3
	light.Parent = part

	local beam
	if rarity >= 2 then
		beam = Instance.new("Part")
		beam.Name = "Beam"
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.CastShadow = false
		beam.Material = Enum.Material.Neon
		beam.Color = color
		beam.Transparency = 0.55
		local height = 8 + rarity * 5
		beam.Size = Vector3.new(0.45 + rarity * 0.1, height, 0.45 + rarity * 0.1)
		beam.CFrame = CFrame.new(ground + Vector3.new(0, height / 2, 0))
		beam.Parent = part
	end

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(190, 28)
	gui.StudsOffset = Vector3.new(0, 2.4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = rarity >= 4 and 160 or 55
	gui.Parent = part
	local label = Kit.text({
		Size = UDim2.fromScale(1, 1),
		Text = info.name,
		TextColor3 = color,
		Font = Kit.BOLD,
		TextSize = 15,
		TextStrokeTransparency = 0.35,
	}, gui)
	label.TextScaled = false

	-- pop-in
	part.Size = part.Size * 0.1
	TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = SHAPE[info.slotKey] or SHAPE.t }):Play()

	drops[id] = { part = part, base = ground + Vector3.new(0, 1.8, 0), t0 = os.clock() + id * 0.37, magnet = false }
end

local function remove(id: number)
	local drop = drops[id]
	if not drop then
		return
	end
	drops[id] = nil
	local part = drop.part
	if part and part.Parent then
		local tween = TweenService:Create(part, TweenInfo.new(0.2), { Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 })
		tween:Play()
		task.delay(0.25, function()
			part:Destroy()
		end)
	end
end

function LootFx.init()
	Remotes.get("LootDrop").OnClientEvent:Connect(spawn)
	Remotes.get("LootTaken").OnClientEvent:Connect(remove)
	RunService.RenderStepped:Connect(function(dt)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local now = os.clock()
		for _, drop in drops do
			local part = drop.part
			if part.Parent then
				local base = drop.base
				if root then
					local away = root.Position - base
					if away.Magnitude < 12 then
						drop.magnet = true
					end
					if drop.magnet then
						base = base + away * math.min(1, dt * 5)
						drop.base = base
					end
				end
				local t = now - drop.t0
				part.CFrame = CFrame.new(base + Vector3.new(0, math.sin(t * 2.4) * 0.3, 0)) * CFrame.Angles(0, t * 1.6, 0)
			end
		end
	end)
end

return LootFx
