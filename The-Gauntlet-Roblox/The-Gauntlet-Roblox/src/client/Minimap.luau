--!nonstrict
-- Corner minimap: a camera-up square showing nearby foes (red), bosses (gold), party (blue) and the
-- quest waypoint (pulsing ring, clamped to the edge). Pure client read of the workspace; no server cost.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Kit = require(script.Parent.Kit)

local Minimap = {}

local SIZE = 156 -- px
local RADIUS = 95 -- studs from centre to edge
local player = Players.LocalPlayer

local box, dotLayer, wayDot
local pool = {} -- reusable dots
local used = 0
local waypoint -- Vector3?

local function dot(color: Color3, px: number): Frame
	used += 1
	local d = pool[used]
	if not d then
		d = Instance.new("Frame")
		d.BorderSizePixel = 0
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		Kit.corner(d, 99)
		d.Parent = dotLayer
		pool[used] = d
	end
	d.Visible = true
	d.BackgroundColor3 = color
	d.Size = UDim2.fromOffset(px, px)
	return d
end

local function place(d: Frame, offsetX: number, offsetY: number, clamp: boolean)
	local half = SIZE / 2 - 4
	local x, y = offsetX / RADIUS * (SIZE / 2), offsetY / RADIUS * (SIZE / 2)
	if clamp then
		local m = math.max(math.abs(x), math.abs(y))
		if m > half then
			x, y = x / m * half, y / m * half
		end
	elseif math.abs(x) > half or math.abs(y) > half then
		d.Visible = false
		return
	end
	d.Position = UDim2.fromOffset(SIZE / 2 + x, SIZE / 2 + y)
end

local function refresh()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not root or not camera then
		return
	end
	local look = camera.CFrame.LookVector
	local yaw = math.atan2(look.X, look.Z) -- rotate world so camera-forward is up
	local c, s = math.cos(yaw), math.sin(yaw)
	local origin = root.Position
	used = 0

	local function toMap(pos: Vector3)
		local dx, dz = pos.X - origin.X, pos.Z - origin.Z
		return dz * s - dx * c, -(dx * s + dz * c) -- right of camera = +x, forward = up
	end

	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then
		for _, model in enemies:GetChildren() do
			local part = model.PrimaryPart
			if part then
				local ox, oy = toMap(part.Position)
				if ox * ox + oy * oy <= RADIUS * RADIUS * 1.2 then
					local boss = model:GetAttribute("Boss")
					place(dot(boss and Color3.fromRGB(255, 190, 90) or Color3.fromRGB(235, 90, 80), boss and 11 or 6), ox, oy, false)
				end
			end
		end
	end
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local r = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if r then
				local ox, oy = toMap(r.Position)
				place(dot(Color3.fromRGB(110, 170, 255), 8), ox, oy, true)
			end
		end
	end
	if waypoint then
		local ox, oy = toMap(waypoint)
		local d = dot(Color3.fromRGB(255, 215, 90), 10 + math.floor(math.abs(math.sin(os.clock() * 3)) * 4))
		place(d, ox, oy, true)
	end
	local me = dot(Color3.fromRGB(255, 255, 255), 9)
	me.Position = UDim2.fromOffset(SIZE / 2, SIZE / 2)
	for i = used + 1, #pool do
		pool[i].Visible = false
	end
end

function Minimap.init(gui: ScreenGui)
	box = Kit.panel({
		Name = "Minimap",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 124),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = Color3.fromRGB(18, 20, 14),
		BackgroundTransparency = 0.15,
		ClipsDescendants = true,
	}, gui)
	dotLayer = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, box)
	Kit.text({ Position = UDim2.fromOffset(0, 1), Size = UDim2.new(1, 0, 0, 12), Text = "N", TextSize = 10, TextColor3 = Kit.UI.muted }, box)

	Remotes.get("Waypoint").OnClientEvent:Connect(function(position)
		waypoint = typeof(position) == "Vector3" and position or nil
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 and box.Visible then
			acc = 0
			refresh()
		end
	end)
end

function Minimap.setVisible(v: boolean)
	if box then
		box.Visible = v
	end
end

return Minimap
