--!nonstrict
-- Combat feel (client): damage numbers, combo counter, hit sparks, FOV punch, dodge roll + afterimages,
-- aim assist (face the nearest enemy when attacking) and a hurt vignette.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Data = require(Shared.Data)
local Palette = require(Shared.Palette)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)
local Kit = require(script.Parent.Kit)

local Feel = {}
Feel.shake = function(_amount: number) end -- set by Main

local player = Players.LocalPlayer
local UI = Kit.UI

local liveNumbers = 0
local comboExpire, comboCount = 0, 0
local comboUi, comboNumber, comboBar
local punch, punching, baseFov = 0, false, 70
local dodging = false
local vignette = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function localParts()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return character, humanoid, root
	end
	return nil, nil, nil
end

-- --------------------------------------------------------------- numbers
local function anchorAt(position: Vector3): Part
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = position
	anchor.Parent = workspace
	return anchor
end

local function popNumber(position: Vector3, amount: number, crit: boolean, own: boolean)
	if liveNumbers > 36 and not own then
		return -- keep co-op fights readable
	end
	liveNumbers += 1
	local jitter = Vector3.new((math.random() - 0.5) * 2.2, 0, (math.random() - 0.5) * 2.2)
	local anchor = anchorAt(position + jitter)
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromOffset(160, 60)
	board.AlwaysOnTop = true
	board.MaxDistance = 150
	board.Adornee = anchor
	board.Parent = anchor
	local size = crit and 36 or own and 25 or 16
	local color = crit and Color3.fromRGB(255, 204, 72) or own and UI.ink or Color3.fromRGB(180, 190, 205)
	local label = Kit.text({
		Size = UDim2.fromScale(1, 1),
		Text = crit and (tostring(amount) .. "!") or tostring(amount),
		Font = Kit.BOLD,
		TextSize = math.floor(size * 0.45),
		TextColor3 = color,
		TextStrokeTransparency = 0.1,
		TextStrokeColor3 = crit and Color3.fromRGB(120, 40, 10) or Color3.fromRGB(30, 22, 16),
		TextTransparency = own and 0 or 0.25,
	}, board)
	Kit.tween(label, 0.14, { TextSize = size }, Enum.EasingStyle.Back)
	local rise = crit and 5.5 or 3.5
	TweenService:Create(anchor, TweenInfo.new(0.95, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = anchor.Position + Vector3.new((math.random() - 0.5) * 2, rise, 0),
	}):Play()
	task.delay(0.55, function()
		if label.Parent then
			Kit.tween(label, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
	end)
	Debris:AddItem(anchor, 1.1)
	task.delay(1.1, function()
		liveNumbers -= 1
	end)
end

local function sparks(position: Vector3, crit: boolean)
	local count = crit and 12 or 6
	local color = crit and Color3.fromRGB(255, 240, 190) or Color3.fromRGB(255, 226, 150)
	for _ = 1, count do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Size = Vector3.new(0.4, 0.4, 0.4)
		p.Position = position
		p.Parent = workspace
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5).Unit
		TweenService:Create(p, TweenInfo.new(crit and 0.4 or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = position + dir * ((crit and 3 or 2) + math.random() * 2),
			Transparency = 1,
			Size = Vector3.new(0.1, 0.1, 0.1),
		}):Play()
		Debris:AddItem(p, 0.45)
	end
end

local function fovPunch(amount: number)
	punch = math.max(punch, amount)
end

-- ------------------------------------------------------------------ combo
local function comboColor(n: number): Color3
	if n >= Config.COMBO_MAX then
		return Color3.fromRGB(255, 120, 70)
	elseif n >= 5 then
		return Color3.fromRGB(255, 204, 72)
	end
	return UI.ink
end

local function showCombo(n: number)
	comboCount = n
	comboExpire = os.clock() + Config.COMBO_WINDOW
	comboUi.Visible = true
	comboNumber.Text = n >= Config.COMBO_MAX and ("x" .. n .. " MAX") or ("x" .. n)
	comboNumber.TextColor3 = comboColor(n)
	comboNumber.TextSize = 60
	Kit.tween(comboNumber, 0.16, { TextSize = 44 }, Enum.EasingStyle.Back)
end

local function hideCombo()
	comboCount = 0
	comboUi.Visible = false
end

-- ----------------------------------------------------------------- vignette
local function buildVignette(gui: ScreenGui)
	local function edge(anchor: Vector2, position: UDim2, size: UDim2, rotation: number)
		local f = Instance.new("Frame")
		f.AnchorPoint = anchor
		f.Position = position
		f.Size = size
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.fromRGB(190, 24, 24)
		f.BackgroundTransparency = 1
		f.ZIndex = 50
		local g = Instance.new("UIGradient")
		g.Rotation = rotation
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = f
		f.Parent = gui
		table.insert(vignette, f)
	end
	edge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(1, 0, 0, 120), 90)
	edge(Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.new(1, 0, 0, 120), -90)
	edge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(0, 120, 1, 0), 0)
	edge(Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.new(0, 120, 1, 0), 180)
end

local function flashVignette(strength: number)
	for _, f in vignette do
		f.BackgroundTransparency = 1 - math.clamp(strength, 0, 0.75)
		Kit.tween(f, 0.5, { BackgroundTransparency = 1 })
	end
end

local function watchHealth(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	hideCombo()
	local last = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < last - 0.5 then
			flashVignette(0.35 + math.clamp((last - health) / math.max(humanoid.MaxHealth, 1), 0, 0.4))
		end
		last = health
	end)
end

-- ------------------------------------------------------------------ dodge
local function ghost(character: Model, color: Color3)
	local model = Instance.new("Model")
	model.Name = "DodgeGhost"
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.9 then
			local c = d:Clone()
			if c then
				for _, child in c:GetChildren() do
					if not child:IsA("DataModelMesh") then
						child:Destroy()
					end
				end
				c.Anchored = true
				c.CanCollide = false
				c.CanQuery = false
				c.CanTouch = false
				c.CastShadow = false
				c.Material = Enum.Material.Neon
				c.Color = color
				c.Transparency = 0.55
				c.Parent = model
				Kit.tween(c, 0.35, { Transparency = 1 })
			end
		end
	end
	model.Parent = workspace
	Debris:AddItem(model, 0.45)
end

local function dustRing(position: Vector3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(220, 210, 180)
	ring.Transparency = 0.6
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.CFrame = CFrame.new(position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	Kit.tween(ring, 0.35, { Size = Vector3.new(0.2, 9, 9), Transparency = 1 })
	Debris:AddItem(ring, 0.4)
end

local function playDodgeFx(userId: number, position: Vector3)
	local who = Players:GetPlayerByUserId(userId)
	local character = who and who.Character
	if not character then
		return
	end
	local info = Data.Heroes[who:GetAttribute("Hero") or "Knight"]
	local color = info and Palette.hex(info.color) or Color3.fromRGB(200, 220, 255)
	dustRing(position)
	for i = 0, 3 do
		task.delay(i * 0.05, function()
			if character.Parent then
				ghost(character, color)
			end
		end)
	end
end

-- Returns true if a roll started. The server grants the i-frames; movement is client-side.
function Feel.dodge(): boolean
	local _, humanoid, root = localParts()
	if not humanoid or dodging then
		return false
	end
	if (player:GetAttribute("DodgeReadyAt") or 0) > workspace:GetServerTimeNow() then
		return false
	end
	local dir = flat(humanoid.MoveDirection)
	if dir.Magnitude < 0.1 then
		dir = flat(root.CFrame.LookVector)
	end
	if dir.Magnitude < 0.05 then
		return false
	end
	dir = dir.Unit
	Remotes.get("Dodge"):FireServer(dir)
	player:SetAttribute("DodgeReadyAt", workspace:GetServerTimeNow() + Config.DODGE_COOLDOWN) -- local mirror
	dodging = true
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	humanoid.AutoRotate = false
	fovPunch(7)
	Feel.shake(0.12)
	local started = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = (os.clock() - started) / Config.DODGE_TIME
		if t >= 1 or humanoid.Health <= 0 or not root.Parent then
			conn:Disconnect()
			humanoid.AutoRotate = true
			dodging = false
			return
		end
		local speed = Config.DODGE_SPEED * (1 - 0.6 * t * t)
		root.AssemblyLinearVelocity = Vector3.new(dir.X * speed, root.AssemblyLinearVelocity.Y, dir.Z * speed)
	end)
	return true
end

function Feel.dodging(): boolean
	return dodging
end

-- 0..1 (1 = ready) for HUD buttons.
function Feel.dodgeReadiness(): number
	local left = (player:GetAttribute("DodgeReadyAt") or 0) - workspace:GetServerTimeNow()
	if left <= 0 then
		return 1
	end
	return math.clamp(1 - left / Config.DODGE_COOLDOWN, 0, 1)
end

-- ------------------------------------------------------------- aim assist
function Feel.faceNearest(range: number)
	if dodging then
		return
	end
	local _, _, root = localParts()
	local folder = workspace:FindFirstChild("Enemies")
	if not root or not folder then
		return
	end
	local best, bestD = nil, range
	for _, model in folder:GetChildren() do
		local pp = model:IsA("Model") and model.PrimaryPart
		if pp then
			local d = flat(pp.Position - root.Position).Magnitude
			if d < bestD and math.abs(pp.Position.Y - root.Position.Y) < 14 then
				best, bestD = pp.Position, d
			end
		end
	end
	if best then
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(best.X, root.Position.Y, best.Z))
	end
end

-- ------------------------------------------------------------------- init
function Feel.init(gui: ScreenGui)
	comboUi = Kit.frame({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.4, 0),
		Size = UDim2.fromOffset(170, 92),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	comboNumber = Kit.text({
		Size = UDim2.new(1, 0, 0, 56),
		Text = "",
		Font = Kit.BOLD,
		TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.2,
	}, comboUi)
	Kit.text({
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 16),
		Text = "COMBO  +dmg  +ult charge",
		TextSize = 11,
		TextColor3 = UI.muted,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, comboUi)
	local track = Kit.frame({ Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = UI.bg, BackgroundTransparency = 0.3 }, comboUi)
	comboBar = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.gold }, track)
	buildVignette(gui)

	Remotes.get("EnemyHit").OnClientEvent:Connect(function(position, amount, crit, attackerId, combo)
		if typeof(position) ~= "Vector3" then
			return
		end
		local own = attackerId == player.UserId
		popNumber(position, math.floor(tonumber(amount) or 0), crit == true, own)
		sparks(position - Vector3.new(0, 2, 0), crit == true)
		if own then
			Sounds.play("hit")
			if crit then
				fovPunch(4)
				Feel.shake(0.12)
			end
			if type(combo) == "number" and combo >= 2 then
				showCombo(combo)
			end
		end
	end)
	Remotes.get("Dodge").OnClientEvent:Connect(function(userId, position)
		if type(userId) == "number" and typeof(position) == "Vector3" then
			playDodgeFx(userId, position)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local cam = workspace.CurrentCamera
		if cam then
			if punch > 0.05 then
				if not punching then
					baseFov = cam.FieldOfView
					punching = true
				end
				punch = math.max(0, punch - dt * 26)
				cam.FieldOfView = baseFov + punch
			elseif punching then
				punching = false
				cam.FieldOfView = baseFov
			end
		end
		if comboUi.Visible then
			local frac = (comboExpire - os.clock()) / Config.COMBO_WINDOW
			if frac <= 0 then
				hideCombo()
			else
				comboBar.Size = UDim2.fromScale(frac, 1)
				comboBar.BackgroundColor3 = comboColor(comboCount)
			end
		end
	end)

	player.CharacterAdded:Connect(watchHealth)
	if player.Character then
		task.spawn(watchHealth, player.Character)
	end
end

Feel.fovPunch = fovPunch
Feel.flashVignette = flashVignette

return Feel
