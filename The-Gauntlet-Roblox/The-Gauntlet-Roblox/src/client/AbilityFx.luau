--!nonstrict
-- Per-ability visuals. The server fires AbilityFx(payload) after every successful cast; every client
-- draws the same props, poses and world effects, so the whole party sees them.
-- payload = { caster = userId, id = abilityId, hero, o = caster position, t = {enemy positions hit},
--   c = center, r = radius (studs), to = end position, from = start position, allies = {userIds},
--   chain = {positions}, delay, duration, fallen = {positions} }
-- Poses move Motor6D joints locally (visible to the casting player); props/effects are visible to all.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local AbilityFx = {}
AbilityFx.shake = function(_amount: number) end -- set by Main

local rad = math.rad
local V3 = Vector3.new
local rng = Random.new()
local UP = V3(0, 1, 0)

-- ------------------------------------------------------------------ primitives

local function mk(props)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	p.Parent = workspace
	return p
end

local function tween(obj, time, goal, style, dir)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function die(obj, time)
	Debris:AddItem(obj, time)
end

local function groundY(pos: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace:FindFirstChild("World") or workspace }
	local r = workspace:Raycast(pos + V3(0, 3, 0), V3(0, -16, 0), params)
	return r and r.Position.Y + 0.15 or pos.Y - 2.85
end

local function ring(center: Vector3, r0: number, r1: number, color: Color3, dur: number, thick: number?, start: number?)
	local p = mk({
		Shape = Enum.PartType.Cylinder,
		Size = V3(thick or 0.3, r0 * 2, r0 * 2),
		CFrame = CFrame.new(center.X, groundY(center), center.Z) * CFrame.Angles(0, 0, rad(90)),
		Color = color,
		Transparency = start or 0.3,
	})
	tween(p, dur, { Size = V3(thick or 0.3, r1 * 2, r1 * 2), Transparency = 1 })
	die(p, dur + 0.1)
	return p
end

local function ball(pos: Vector3, size: number, grow: number, color: Color3, dur: number, transp: number?)
	local p = mk({ Shape = Enum.PartType.Ball, Size = V3(size, size, size), Position = pos, Color = color, Transparency = transp or 0.2 })
	tween(p, dur, { Size = V3(grow, grow, grow), Transparency = 1 })
	die(p, dur + 0.1)
	return p
end

-- n small bits flying outward (and up) from pos.
local function burst(pos: Vector3, color: Color3, n: number, speed: number, size: number?, dur: number?, upward: number?, material)
	dur = dur or 0.45
	for _ = 1, n do
		local dir = V3(rng:NextNumber(-1, 1), rng:NextNumber(0, 1) * (upward or 0.6), rng:NextNumber(-1, 1))
		if dir.Magnitude < 0.1 then
			dir = UP
		end
		local s = size or 0.5
		local p = mk({ Size = V3(s, s, s), Position = pos, Color = color, Material = material or Enum.Material.Neon })
		tween(p, dur, { Position = pos + dir.Unit * speed * rng:NextNumber(0.5, 1), Transparency = 1, Size = V3(s * 0.3, s * 0.3, s * 0.3) })
		die(p, dur + 0.1)
	end
end

local function spark(pos: Vector3, color: Color3, size: number?)
	ball(pos, 0.5, size or 4, Color3.new(1, 1, 1), 0.18, 0.1)
	ball(pos, 0.5, (size or 4) * 1.5, color, 0.3, 0.35)
	burst(pos, color, 7, (size or 4) * 1.3, 0.35, 0.3)
end

-- jagged beam (lightning / piercing flash).
local function zig(a: Vector3, b: Vector3, color: Color3, width: number?, dur: number?)
	dur = dur or 0.22
	local dist = (b - a).Magnitude
	if dist < 0.5 then
		return
	end
	local segs = math.clamp(math.floor(dist / 3), 3, 14)
	local dir = (b - a).Unit
	local side = dir:Cross(UP)
	if side.Magnitude < 0.1 then
		side = V3(1, 0, 0)
	end
	side = side.Unit
	local prev = a
	for i = 1, segs do
		local nextP = a + dir * (dist * i / segs)
		if i < segs then
			nextP += side * rng:NextNumber(-1.4, 1.4) + UP * rng:NextNumber(-1, 1)
		end
		local len = (nextP - prev).Magnitude
		local p = mk({ Size = V3(width or 0.35, width or 0.35, len), CFrame = CFrame.lookAt(prev, nextP) * CFrame.new(0, 0, -len / 2), Color = color })
		tween(p, dur, { Transparency = 1 })
		die(p, dur + 0.05)
		prev = nextP
	end
end

local function projectile(a: Vector3, b: Vector3, color: Color3, size: number, speed: number?, shape, onHit, length: number?)
	local dist = (b - a).Magnitude
	local flight = math.clamp(dist / (speed or 120), 0.06, 0.6)
	local p = mk({
		Shape = shape or Enum.PartType.Ball,
		Size = shape == Enum.PartType.Block and V3(size, size, length or size * 3) or V3(size, size, size),
		CFrame = CFrame.lookAt(a, b),
		Color = color,
	})
	tween(p, flight, { CFrame = CFrame.lookAt(b, b + (b - a)) }, Enum.EasingStyle.Linear)
	-- trail
	local trail = mk({ Size = V3(size * 0.45, size * 0.45, dist), CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -dist / 2), Color = color, Transparency = 0.45 })
	tween(trail, flight + 0.15, { Transparency = 1, Size = V3(0.05, 0.05, dist) })
	die(trail, flight + 0.2)
	die(p, flight + 0.02)
	task.delay(flight, function()
		if onHit then
			onHit()
		end
	end)
	return flight
end

-- Floating glyph (music notes, "!", plus signs) that rises and fades.
local function glyph(pos: Vector3, text: string, color: Color3, rise: number?, size: number?, dur: number?)
	dur = dur or 0.9
	local anchor = mk({ Size = V3(0.2, 0.2, 0.2), Position = pos, Transparency = 1 })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(size or 36, size or 36)
	gui.AlwaysOnTop = true
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
	tween(anchor, dur, { Position = pos + V3(rng:NextNumber(-1, 1), rise or 4, rng:NextNumber(-1, 1)) })
	tween(label, dur, { TextTransparency = 1, TextStrokeTransparency = 1 })
	die(anchor, dur + 0.1)
end

-- Ground cracks radiating from a point.
local function cracks(center: Vector3, radius: number, n: number)
	local y = groundY(center)
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local len = radius * rng:NextNumber(0.6, 1)
		local dir = V3(math.cos(a), 0, math.sin(a))
		local p = mk({
			Size = V3(0.5, 0.15, 0.5),
			CFrame = CFrame.lookAt(V3(center.X, y, center.Z), V3(center.X, y, center.Z) + dir),
			Color = Color3.fromRGB(38, 30, 24),
			Material = Enum.Material.Slate,
			Transparency = 0,
		})
		tween(p, 0.25, { Size = V3(0.9, 0.15, len), CFrame = CFrame.lookAt(V3(center.X, y, center.Z), V3(center.X, y, center.Z) + dir) * CFrame.new(0, 0, -len / 2) })
		task.delay(0.6, function()
			if p.Parent then
				tween(p, 0.8, { Transparency = 1 }, Enum.EasingStyle.Linear)
			end
		end)
		die(p, 1.6)
	end
end

local function debris(center: Vector3, radius: number, n: number, color: Color3?)
	local y = groundY(center)
	for _ = 1, n do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(0.3, 1) * radius
		local landing = V3(center.X + math.cos(a) * d, y + 0.5, center.Z + math.sin(a) * d)
		local s = rng:NextNumber(0.8, 2)
		local rock = mk({ Size = V3(s, s, s), CFrame = CFrame.new(center.X, y + 0.5, center.Z) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0), Color = color or Color3.fromRGB(96, 88, 78), Material = Enum.Material.Slate })
		local mid = V3((center.X + landing.X) / 2, y + rng:NextNumber(5, 11), (center.Z + landing.Z) / 2)
		tween(rock, 0.28, { Position = mid, Orientation = V3(rng:NextNumber(0, 360), rng:NextNumber(0, 360), 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out).Completed:Once(function()
			if rock.Parent then
				tween(rock, 0.3, { Position = landing }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				tween(rock, 0.9, { Transparency = 1 }, Enum.EasingStyle.Linear)
			end
		end)
		die(rock, 1.6)
	end
end

local function pillar(pos: Vector3, color: Color3, height: number, radius: number, dur: number)
	local y = groundY(pos)
	local p = mk({
		Shape = Enum.PartType.Cylinder,
		Size = V3(1, radius * 2, radius * 2),
		CFrame = CFrame.new(pos.X, y + 0.5, pos.Z) * CFrame.Angles(0, 0, rad(90)),
		Color = color,
		Transparency = 0.4,
	})
	tween(p, dur * 0.4, { Size = V3(height, radius * 2, radius * 2), CFrame = CFrame.new(pos.X, y + height / 2, pos.Z) * CFrame.Angles(0, 0, rad(90)) })
	task.delay(dur * 0.5, function()
		if p.Parent then
			tween(p, dur * 0.5, { Transparency = 1, Size = V3(height, 0.2, 0.2) })
		end
	end)
	die(p, dur + 0.1)
end

local function windLines(root: BasePart, color: Color3, n: number)
	for _ = 1, n do
		local off = V3(rng:NextNumber(-2.5, 2.5), rng:NextNumber(-2, 2.5), rng:NextNumber(0.5, 3))
		local a = root.CFrame * CFrame.new(off)
		local p = mk({ Size = V3(0.12, 0.12, 4), CFrame = a, Color = color, Transparency = 0.2 })
		tween(p, 0.35, { CFrame = a * CFrame.new(0, 0, 7), Transparency = 1 }, Enum.EasingStyle.Linear)
		die(p, 0.45)
	end
end

-- Persistent glow that follows a root part: "dome" shield bubble, "column" light shaft, "rings" rising halos.
local function aura(root: BasePart, color: Color3, dur: number, style: string)
	local parts = {}
	if style == "dome" then
		local shell = mk({ Shape = Enum.PartType.Ball, Size = V3(8, 8, 8), Color = color, Material = Enum.Material.ForceField, Transparency = 0.45 })
		local band = mk({ Shape = Enum.PartType.Cylinder, Size = V3(0.25, 7.4, 7.4), Color = color, Transparency = 0.3 })
		parts = { shell, band }
		shell.Size = V3(2, 2, 2)
		tween(shell, 0.3, { Size = V3(8, 8, 8) }, Enum.EasingStyle.Back)
	elseif style == "column" then
		parts = { mk({ Shape = Enum.PartType.Cylinder, Size = V3(14, 3.2, 3.2), Color = color, Transparency = 0.62 }) }
	end
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if t >= dur or not root.Parent then
			conn:Disconnect()
			for _, p in parts do
				if p.Parent then
					tween(p, 0.4, { Transparency = 1 })
					die(p, 0.5)
				end
			end
			return
		end
		local pos = root.Position
		if style == "dome" then
			parts[1].CFrame = CFrame.new(pos)
			parts[2].CFrame = CFrame.new(pos + V3(0, math.sin(t * 2.2) * 2.2, 0)) * CFrame.Angles(0, 0, rad(90))
		else
			parts[1].CFrame = CFrame.new(pos + V3(0, 3, 0)) * CFrame.Angles(0, t * 2, rad(90))
		end
		if style == "column" and rng:NextNumber() < 0.35 then
			local o = V3(rng:NextNumber(-1.5, 1.5), -2.8, rng:NextNumber(-1.5, 1.5))
			local s = mk({ Size = V3(0.3, 0.3, 0.3), Position = pos + o, Color = color })
			tween(s, 0.7, { Position = pos + o + V3(0, 8, 0), Transparency = 1 }, Enum.EasingStyle.Linear)
			die(s, 0.8)
		end
	end)
end

-- Sparkles rising around a character for `dur` seconds.
local function risers(root: BasePart, color: Color3, dur: number, text: string?)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < dur and root.Parent do
			local o = V3(rng:NextNumber(-2, 2), -2.5, rng:NextNumber(-2, 2))
			if text then
				glyph(root.Position + o + V3(0, 1, 0), text, color, 5, 26, 0.9)
			else
				local s = mk({ Size = V3(0.35, 0.35, 0.35), Position = root.Position + o, Color = color })
				tween(s, 0.8, { Position = root.Position + o + V3(0, 6, 0), Transparency = 1 }, Enum.EasingStyle.Linear)
				die(s, 0.9)
			end
			task.wait(0.07)
		end
	end)
end

-- Arc swing of a bright blade in front of the caster. tilt = roll of the arc plane (90 = overhead chop).
local function slash(root: BasePart, o)
	local radius, from, to, tilt, dur = o.radius or 5.5, o.from or -85, o.to or 85, o.tilt or 0, o.dur or 0.2
	local color = o.color or Color3.new(1, 1, 1)
	local head = mk({ Size = V3(o.width or 0.5, o.width or 0.5, o.len or 5), Color = color })
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - t0) / dur
		if t >= 1 or not root.Parent then
			conn:Disconnect()
			head:Destroy()
			return
		end
		local frame = root.CFrame * CFrame.Angles(0, 0, rad(tilt)) * CFrame.Angles(0, rad(from + (to - from) * t), 0) * CFrame.new(0, o.height or 0.8, -radius)
		head.CFrame = frame * CFrame.Angles(0, rad(90), 0)
		local ghost = mk({ Size = head.Size, CFrame = head.CFrame, Color = color, Transparency = 0.35 })
		tween(ghost, 0.2, { Transparency = 1, Size = V3(0.1, 0.1, head.Size.Z) }, Enum.EasingStyle.Linear)
		die(ghost, 0.25)
	end)
end

-- ------------------------------------------------------------------ props + poses

local function handOf(character: Model, side: string): BasePart?
	if side == "R" then
		return character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	end
	return character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
end

local function weld(hand: BasePart, part: BasePart, offset: CFrame)
	part.Anchored = false
	part.Massless = true
	local w = Instance.new("Weld")
	w.Part0, w.Part1 = hand, part
	w.C0 = offset
	w.Parent = part
end

local function prop(character: Model, kind: string, side: string, color: Color3, dur: number)
	local hand = handOf(character, side)
	if not hand then
		return
	end
	local parts = {}
	local function add(props, offset)
		props.Material = props.Material or Enum.Material.Metal
		local p = mk(props)
		weld(hand, p, offset)
		table.insert(parts, p)
	end
	local steel, wood, gold = Color3.fromRGB(190, 198, 210), Color3.fromRGB(110, 80, 52), Color3.fromRGB(226, 188, 90)
	if kind == "shield" then
		add({ Shape = Enum.PartType.Cylinder, Size = V3(0.45, 3.4, 3.4), Color = steel }, CFrame.new(0, -1.1, 0) * CFrame.Angles(0, 0, rad(90)))
		add({ Shape = Enum.PartType.Cylinder, Size = V3(0.6, 3.7, 3.7), Color = gold }, CFrame.new(0, -1.0, 0) * CFrame.Angles(0, 0, rad(90)))
		add({ Shape = Enum.PartType.Ball, Size = V3(0.9, 0.9, 0.9), Color = color, Material = Enum.Material.Neon }, CFrame.new(0, -1.5, 0))
	elseif kind == "sword" then
		add({ Size = V3(0.3, 4.4, 0.9), Color = steel }, CFrame.new(0, -3.2, 0))
		add({ Size = V3(0.3, 4.4, 0.25), Color = color, Material = Enum.Material.Neon, Transparency = 0.35 }, CFrame.new(0, -3.2, 0))
		add({ Size = V3(0.5, 0.35, 2), Color = gold }, CFrame.new(0, -1, 0))
	elseif kind == "staff" then
		add({ Size = V3(0.35, 6.5, 0.35), Color = wood, Material = Enum.Material.Wood }, CFrame.new(0, -2, 0))
		add({ Shape = Enum.PartType.Ball, Size = V3(1.1, 1.1, 1.1), Color = color, Material = Enum.Material.Neon }, CFrame.new(0, -5.4, 0))
	elseif kind == "bow" then
		add({ Size = V3(0.3, 0.3, 4.2), Color = wood, Material = Enum.Material.Wood }, CFrame.new(0, -1.2, 0))
		add({ Size = V3(0.1, 0.1, 4), Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon, Transparency = 0.3 }, CFrame.new(0.5, -1.2, 0))
	elseif kind == "flask" then
		add({ Shape = Enum.PartType.Ball, Size = V3(1.2, 1.2, 1.2), Color = Color3.fromRGB(220, 235, 240), Material = Enum.Material.Glass, Transparency = 0.4 }, CFrame.new(0, -1.1, 0))
		add({ Shape = Enum.PartType.Ball, Size = V3(0.8, 0.8, 0.8), Color = color, Material = Enum.Material.Neon }, CFrame.new(0, -1.1, 0))
	elseif kind == "dagger" then
		add({ Size = V3(0.2, 2.2, 0.55), Color = steel }, CFrame.new(0, -1.7, 0))
		add({ Size = V3(0.3, 0.3, 0.9), Color = Color3.fromRGB(40, 36, 44) }, CFrame.new(0, -0.7, 0))
	elseif kind == "lute" then
		add({ Size = V3(1.8, 0.5, 1.8), Color = wood, Material = Enum.Material.Wood }, CFrame.new(0, -1.2, 0))
		add({ Size = V3(0.3, 3, 0.3), Color = wood, Material = Enum.Material.Wood }, CFrame.new(0, -3, 0))
		add({ Size = V3(0.15, 3, 0.15), Color = color }, CFrame.new(0, -3, 0.45))
	elseif kind == "wand" then
		add({ Size = V3(0.25, 3.6, 0.25), Color = wood, Material = Enum.Material.Wood }, CFrame.new(0, -1.6, 0))
		add({ Shape = Enum.PartType.Ball, Size = V3(0.9, 0.9, 0.9), Color = color, Material = Enum.Material.Neon }, CFrame.new(0, -3.5, 0))
	end
	for _, p in parts do
		die(p, dur + 0.3)
		task.delay(dur, function()
			if p.Parent then
				tween(p, 0.25, { Transparency = 1 })
			end
		end)
	end
	return parts
end

local function motor(character: Model, side: string): Motor6D?
	local names = side == "R" and { "RightShoulder", "Right Shoulder" } or { "LeftShoulder", "Left Shoulder" }
	for _, n in names do
		local m = character:FindFirstChild(n, true)
		if m and m:IsA("Motor6D") then
			return m
		end
	end
	return nil
end

-- angles in degrees {x, y, z}; x < 0 raises the arm forward.
local function pose(character: Model, spec)
	for side, key in { R = "r", L = "l" } do
		local a = spec[key]
		local m = a and motor(character, side)
		if m then
			local base = m:GetAttribute("BaseC0")
			if not base then
				base = m.C0
				m:SetAttribute("BaseC0", base)
			end
			local target = base * CFrame.Angles(rad(a[1]), rad(a[2] or 0), rad(a[3] or 0))
			local up = TweenService:Create(m, TweenInfo.new(spec.t or 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = target })
			up.Completed:Once(function()
				task.delay(spec.hold or 0.15, function()
					if m.Parent then
						TweenService:Create(m, TweenInfo.new(spec.back or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { C0 = base }):Play()
					end
				end)
			end)
			up:Play()
		end
	end
end

-- ------------------------------------------------------------------ helpers over payload

local function charOf(userId: number): Model?
	local p = Players:GetPlayerByUserId(userId)
	return p and p.Character
end

local function rootOfId(userId: number): BasePart?
	local c = charOf(userId)
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function allyRoots(d, includeCaster: boolean?)
	local list = {}
	for _, id in d.allies or {} do
		local r = rootOfId(id)
		if r and (includeCaster ~= false or id ~= d.caster) then
			table.insert(list, r)
		end
	end
	return list
end

local function head(root: BasePart): Vector3
	return root.Position + V3(0, 2.5, 0)
end

local function handPos(c): Vector3
	local hand = handOf(c.char, "R")
	return hand and hand.Position or (c.root.Position + c.root.CFrame.LookVector * 2 + V3(0, 1, 0))
end

local function each(list, fn)
	for _, v in list or {} do
		fn(v)
	end
end

-- ------------------------------------------------------------------ the abilities

local A = {}

-- Knight -----------------------------------------------------------------------
function A.shield_bash(c)
	local d = c.d
	prop(c.char, "shield", "L", c.color, 0.7)
	pose(c.char, { r = { -80 }, l = { -95 }, t = 0.07, hold = 0.2 })
	local at = d.t and d.t[1] or (c.root.Position + c.root.CFrame.LookVector * 5)
	windLines(c.root, Color3.new(1, 1, 1), 5)
	task.delay(0.08, function()
		spark(at + V3(0, 2, 0), c.color, 5)
		ring(at, 1, 8, c.color, 0.3)
		AbilityFx.shake(0.3)
	end)
end

function A.cleaving_arc(c)
	prop(c.char, "sword", "R", c.color, 0.6)
	pose(c.char, { r = { -90, 0, 30 }, t = 0.05, hold = 0.2 })
	slash(c.root, { radius = math.max(5, c.d.r or 6), from = -100, to = 100, color = Color3.new(1, 1, 1), len = 6, dur = 0.2 })
	task.delay(0.1, function()
		each(c.d.t, function(p)
			spark(p + V3(0, 2, 0), c.color, 3.5)
		end)
	end)
end

function A.iron_wall(c)
	prop(c.char, "shield", "L", c.color, 1.2)
	pose(c.char, { r = { -70, 0, -40 }, l = { -70, 0, 40 }, t = 0.1, hold = 0.8, back = 0.3 })
	ring(c.root.Position, 1, 7, c.color, 0.5, 0.4)
	aura(c.root, Color3.fromRGB(176, 196, 224), c.d.duration or 8, "dome")
	debris(c.root.Position, 4, 5, Color3.fromRGB(150, 160, 172))
end

function A.challenge(c)
	pose(c.char, { r = { -150 }, l = { -150 }, t = 0.12, hold = 0.4 })
	for i = 1, 3 do
		task.delay((i - 1) * 0.12, function()
			ring(c.root.Position, 2, 9 + i * 3, Color3.fromRGB(240, 90, 80), 0.55, 0.3, 0.2)
		end)
	end
	glyph(head(c.root) + V3(0, 1.5, 0), "!", Color3.fromRGB(255, 80, 70), 3, 54, 1.4)
	AbilityFx.shake(0.2)
end

local function banner(c, color)
	local back = c.root.CFrame
	local pole = mk({ Size = V3(0.35, 11, 0.35), CFrame = back * CFrame.new(0, 3, 3), Color = Color3.fromRGB(110, 80, 52), Material = Enum.Material.Wood })
	local flag = mk({ Size = V3(0.15, 3.2, 5), CFrame = back * CFrame.new(0, 6.5, 5.2), Color = color, Material = Enum.Material.Fabric, Transparency = 0.1 })
	pole.CFrame = back * CFrame.new(0, -6, 3)
	flag.Transparency = 1
	tween(pole, 0.35, { CFrame = back * CFrame.new(0, 3, 3) }, Enum.EasingStyle.Back)
	tween(flag, 0.4, { Transparency = 0.1 })
	task.delay(1.4, function()
		tween(flag, 0.5, { Transparency = 1 })
		tween(pole, 0.5, { Transparency = 1 })
	end)
	die(pole, 2.1)
	die(flag, 2.1)
end

function A.guardian_cry(c)
	pose(c.char, { r = { -170 }, l = { -20 }, t = 0.12, hold = 0.5 })
	banner(c, Color3.fromRGB(226, 188, 90))
	ring(c.root.Position, 2, 24, Color3.fromRGB(226, 188, 90), 0.7, 0.4)
	each(allyRoots(c.d), function(r)
		aura(r, Color3.fromRGB(240, 205, 110), c.d.duration or 8, "dome")
	end)
	AbilityFx.shake(0.15)
end

function A.earthshaker(c)
	local r = math.max(c.d.r or 30, 10)
	pose(c.char, { r = { -170 }, l = { -170 }, t = 0.18, hold = 0.12, back = 0.25 })
	task.delay(0.22, function()
		pose(c.char, { r = { -20 }, l = { -20 }, t = 0.05, hold = 0.2 })
		local at = c.root.Position
		cracks(at, r, 14)
		debris(at, r * 0.8, 16)
		for i = 1, 3 do
			task.delay((i - 1) * 0.09, function()
				ring(at, 2, r * (0.55 + i * 0.25), Color3.fromRGB(190, 150, 100), 0.5, 0.5, 0.15)
			end)
		end
		burst(at + V3(0, 0.5, 0), Color3.fromRGB(200, 170, 130), 24, r * 0.6, 1, 0.6, 0.3, Enum.Material.SmoothPlastic)
		each(c.d.t, function(p)
			spark(p + V3(0, 1, 0), Color3.fromRGB(230, 190, 120), 4)
		end)
		AbilityFx.shake(0.9)
	end)
end

-- Wizard -----------------------------------------------------------------------
local VIOLET = Color3.fromRGB(166, 139, 255)

function A.arc_burst(c)
	prop(c.char, "staff", "R", VIOLET, 0.6)
	pose(c.char, { r = { -95 }, t = 0.08, hold = 0.25 })
	local from = handPos(c) + V3(0, 1, 0)
	local first = c.d.t and c.d.t[1]
	if first then
		local p = first + V3(0, 2, 0)
		zig(from, p, Color3.fromRGB(190, 170, 255), 0.5, 0.3)
		spark(p, VIOLET, 4)
		local prev = p
		each(c.d.chain, function(q)
			local qq = q + V3(0, 2, 0)
			zig(prev, qq, Color3.fromRGB(220, 205, 255), 0.4, 0.3)
			spark(qq, VIOLET, 3)
			prev = qq
		end)
	end
end

function A.frost_lance(c)
	local ICE = Color3.fromRGB(150, 220, 255)
	prop(c.char, "staff", "R", ICE, 0.6)
	pose(c.char, { r = { -95 }, t = 0.08, hold = 0.25 })
	local at = c.d.t and c.d.t[1]
	if not at then
		return
	end
	local p = at + V3(0, 2, 0)
	projectile(handPos(c), p, ICE, 0.9, 150, Enum.PartType.Block, function()
		spark(p, ICE, 4)
		ball(p, 3, 8, Color3.fromRGB(190, 235, 255), 0.9, 0.55).Material = Enum.Material.Glass
		for i = 1, 7 do
			local a = (i / 7) * math.pi * 2
			local shard = mk({ Size = V3(0.7, 3.5, 0.7), CFrame = CFrame.new(at + V3(math.cos(a) * 2.5, 1.5, math.sin(a) * 2.5)) * CFrame.Angles(rad(rng:NextNumber(-25, 25)), 0, rad(rng:NextNumber(-25, 25))), Color = ICE, Material = Enum.Material.Glass, Transparency = 0.25 })
			tween(shard, 1, { Transparency = 1 }, Enum.EasingStyle.Linear)
			die(shard, 1.1)
		end
	end, 4.5)
end

function A.spell_surge(c)
	prop(c.char, "staff", "R", VIOLET, 1)
	pose(c.char, { r = { -160 }, t = 0.12, hold = 0.5 })
	ring(c.root.Position, 1.5, 8, VIOLET, 0.6, 0.35)
	aura(c.root, VIOLET, c.d.duration or 8, "column")
	risers(c.root, Color3.fromRGB(210, 195, 255), 0.8)
end

function A.blink(c)
	local from, to = c.d.from or c.d.o, c.d.to
	if from then
		ball(from, 2, 8, VIOLET, 0.35)
		burst(from, VIOLET, 14, 6, 0.5, 0.4)
	end
	if to then
		ball(to, 8, 2, VIOLET, 0.35, 0.4)
		burst(to, Color3.fromRGB(220, 205, 255), 14, 6, 0.5, 0.4)
		if from then
			zig(from, to, Color3.fromRGB(220, 205, 255), 0.4, 0.25)
		end
	end
end

function A.team_aegis(c)
	pose(c.char, { r = { -120 }, l = { -120 }, t = 0.1, hold = 0.4 })
	ring(c.root.Position, 2, 14, VIOLET, 0.6, 0.4)
	each(allyRoots(c.d), function(r)
		aura(r, Color3.fromRGB(190, 170, 255), c.d.duration or 8, "dome")
	end)
end

function A.arcane_cataclysm(c)
	local r = math.max(c.d.r or 40, 12)
	prop(c.char, "staff", "R", VIOLET, 1.1)
	pose(c.char, { r = { -170 }, t = 0.15, hold = 0.5 })
	local at = c.root.Position
	ring(at, 2, r, VIOLET, 0.9, 0.5, 0.1)
	ring(at, 1, r * 0.7, Color3.fromRGB(220, 205, 255), 0.9, 0.5, 0.1)
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2
		local pos = at + V3(math.cos(a) * r * 0.75, 0, math.sin(a) * r * 0.75)
		task.delay(0.15 + i * 0.03, function()
			pillar(pos, VIOLET, 22, 1.2, 0.5)
		end)
	end
	task.delay(0.55, function()
		ball(at + V3(0, 3, 0), 4, r * 1.6, VIOLET, 0.5, 0.35)
		each(c.d.t, function(p)
			spark(p + V3(0, 2, 0), VIOLET, 5)
		end)
		AbilityFx.shake(1)
	end)
end

-- Archer -----------------------------------------------------------------------
local GREEN = Color3.fromRGB(139, 212, 123)

function A.piercing_volley(c)
	prop(c.char, "bow", "L", GREEN, 0.6)
	pose(c.char, { l = { -95 }, r = { -80, 0, 20 }, t = 0.07, hold = 0.25 })
	local from = handPos(c)
	local dir = c.d.dir or c.root.CFrame.LookVector
	local to = from + dir * (c.d.range or 40)
	projectile(from, to, Color3.fromRGB(240, 255, 220), 0.35, 260, Enum.PartType.Block, nil, 3.5)
	each(c.d.t, function(p)
		task.delay(0.08, function()
			spark(p + V3(0, 2, 0), GREEN, 3.5)
		end)
	end)
end

function A.snare_shot(c)
	prop(c.char, "bow", "L", GREEN, 0.6)
	pose(c.char, { l = { -95 }, r = { -80, 0, 20 }, t = 0.07, hold = 0.25 })
	local at = c.d.t and c.d.t[1]
	if at then
		local p = at + V3(0, 2, 0)
		projectile(handPos(c), p, Color3.fromRGB(240, 255, 220), 0.35, 240, Enum.PartType.Block, function()
			spark(p, GREEN, 3)
			for i = 1, 3 do
				ring(at, 1 + i * 0.6, 3 + i, Color3.fromRGB(110, 150, 70), 0.9, 0.25, 0.1)
			end
		end, 3)
	end
end

function A.eagle_eye(c)
	pose(c.char, { r = { -30, 0, 70 }, t = 0.1, hold = 0.5 })
	ring(c.root.Position, 1.5, 7, Color3.fromRGB(255, 220, 120), 0.6, 0.3)
	aura(c.root, Color3.fromRGB(255, 225, 130), c.d.duration or 8, "column")
	local p = head(c.root) + V3(0, 2.2, 0)
	for i = 1, 2 do
		ring(p, 0.6 * i, 1.6 * i, Color3.fromRGB(255, 230, 140), 0.9, 0.2, 0.1)
	end
	glyph(p, "◉", Color3.fromRGB(255, 225, 130), 2, 40, 1.1)
end

function A.quickstep(c)
	pose(c.char, { r = { 40 }, l = { -40 }, t = 0.08, hold = 0.4 })
	windLines(c.root, Color3.fromRGB(220, 255, 220), 10)
	burst(c.root.Position - V3(0, 2.6, 0), Color3.fromRGB(200, 190, 160), 10, 4, 0.6, 0.5, 0.3, Enum.Material.SmoothPlastic)
	risers(c.root, Color3.fromRGB(200, 255, 200), 0.5)
end

function A.rain_of_arrows(c)
	local center = c.d.c
	local r = math.max(c.d.r or 14, 5)
	local delay = c.d.delay or 0.65
	prop(c.char, "bow", "L", GREEN, 0.8)
	pose(c.char, { l = { -140 }, r = { -120, 0, 20 }, t = 0.1, hold = 0.4 })
	if not center then
		return
	end
	projectile(handPos(c), center + V3(0, 45, 0), Color3.fromRGB(240, 255, 220), 0.3, 300, Enum.PartType.Block, nil, 3)
	local marker = ring(center, r, r, Color3.fromRGB(255, 120, 90), delay, 0.25, 0.45)
	marker.Transparency = 0.45
	for i = 1, 22 do
		task.delay(delay * 0.55 + (i / 22) * delay * 0.45, function()
			local a, d = rng:NextNumber(0, math.pi * 2), math.sqrt(rng:NextNumber()) * r
			local land = center + V3(math.cos(a) * d, 0, math.sin(a) * d)
			local top = land + V3(rng:NextNumber(-2, 2), 40, rng:NextNumber(-2, 2))
			local arrow = mk({ Size = V3(0.2, 0.2, 3), CFrame = CFrame.lookAt(top, land), Color = Color3.fromRGB(240, 255, 220) })
			tween(arrow, 0.18, { CFrame = CFrame.lookAt(land, land + (land - top)) }, Enum.EasingStyle.Linear)
			die(arrow, 0.22)
			task.delay(0.18, function()
				burst(land, GREEN, 3, 2, 0.3, 0.25)
			end)
		end)
	end
	task.delay(delay, function()
		ring(center, 2, r, Color3.fromRGB(255, 240, 200), 0.35, 0.4, 0.1)
		each(c.d.t, function(p)
			spark(p + V3(0, 1.5, 0), GREEN, 3)
		end)
		AbilityFx.shake(0.35)
	end)
end

function A.deadeye(c)
	prop(c.char, "bow", "L", GREEN, 0.9)
	pose(c.char, { l = { -95 }, r = { -75, 0, 25 }, t = 0.15, hold = 0.35 })
	local at = c.d.t and c.d.t[1]
	if not at then
		return
	end
	local from = handPos(c)
	ball(from, 0.5, 3.5, Color3.fromRGB(255, 255, 255), 0.25, 0.1)
	task.delay(0.18, function()
		local p = at + V3(0, 2, 0)
		projectile(from, p, Color3.fromRGB(255, 244, 190), 0.8, 320, Enum.PartType.Block, function()
			spark(p, Color3.fromRGB(255, 230, 140), 7)
			ring(at, 1, 10, Color3.fromRGB(255, 230, 140), 0.35)
			AbilityFx.shake(0.5)
		end, 5)
	end)
end

-- Cleric -----------------------------------------------------------------------
local GOLD = Color3.fromRGB(255, 226, 138)

local function lob(from: Vector3, to: Vector3, color: Color3, onHit)
	local flask = mk({ Shape = Enum.PartType.Ball, Size = V3(1.1, 1.1, 1.1), Position = from, Color = color })
	local mid = (from + to) / 2 + V3(0, 7, 0)
	tween(flask, 0.2, { Position = mid }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out).Completed:Once(function()
		tween(flask, 0.2, { Position = to }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
			flask:Destroy()
			if onHit then
				onHit()
			end
		end)
	end)
	die(flask, 0.6)
end

function A.radiant_flask(c)
	prop(c.char, "flask", "R", GOLD, 0.35)
	pose(c.char, { r = { -150 }, t = 0.09, hold = 0.12 })
	local at = c.d.t and c.d.t[1]
	if not at then
		return
	end
	local p = at + V3(0, 1, 0)
	task.delay(0.1, function()
		lob(handPos(c), p, GOLD, function()
			local r = c.d.r or 9
			ball(p, 2, r * 2, GOLD, 0.45, 0.3)
			ring(at, 1, r, Color3.fromRGB(255, 244, 200), 0.45, 0.4)
			for i = 1, 8 do
				local a = (i / 8) * math.pi * 2
				zig(p, p + V3(math.cos(a) * r, 1, math.sin(a) * r), GOLD, 0.3, 0.3)
			end
			burst(p, GOLD, 16, r, 0.5, 0.5)
		end)
	end)
end

function A.sanctified_throw(c)
	prop(c.char, "wand", "R", GOLD, 0.4)
	pose(c.char, { r = { -100 }, t = 0.08, hold = 0.2 })
	local at = c.d.t and c.d.t[1]
	if at then
		local p = at + V3(0, 2, 0)
		projectile(handPos(c), p, Color3.fromRGB(255, 244, 190), 1, 170, nil, function()
			spark(p, GOLD, 4)
			local cross1 = mk({ Size = V3(0.5, 5, 0.5), CFrame = CFrame.new(p), Color = GOLD })
			local cross2 = mk({ Size = V3(3.2, 0.5, 0.5), CFrame = CFrame.new(p + V3(0, 0.6, 0)), Color = GOLD })
			tween(cross1, 0.4, { Transparency = 1 })
			tween(cross2, 0.4, { Transparency = 1 })
			die(cross1, 0.5)
			die(cross2, 0.5)
		end)
	end
end

local HEAL = Color3.fromRGB(130, 245, 160)

function A.splash_mend(c)
	prop(c.char, "flask", "R", HEAL, 0.5)
	pose(c.char, { r = { -140 }, t = 0.1, hold = 0.2 })
	ring(c.root.Position, 2, math.max(c.d.r or 16, 10), HEAL, 0.6, 0.35)
	each(allyRoots(c.d), function(r)
		ring(r.Position, 1, 5, HEAL, 0.5)
		risers(r, HEAL, 0.7, "+")
	end)
end

function A.blessed_vial(c)
	prop(c.char, "flask", "R", GOLD, 0.5)
	pose(c.char, { r = { -140 }, t = 0.1, hold = 0.2 })
	ring(c.root.Position, 2, math.max(c.d.r or 27, 12), GOLD, 0.6, 0.35)
	each(allyRoots(c.d), function(r)
		aura(r, GOLD, c.d.duration or 8, "dome")
	end)
end

function A.sanctuary_rain(c)
	pose(c.char, { r = { -165 }, l = { -165 }, t = 0.12, hold = 0.6 })
	local at = c.root.Position
	ring(at, 2, 20, GOLD, 1.1, 0.4, 0.15)
	ring(at, 1, 13, HEAL, 1, 0.4, 0.15)
	for _ = 1, 28 do
		task.delay(rng:NextNumber(0, 0.9), function()
			local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, 18)
			local pos = at + V3(math.cos(a) * d, 22, math.sin(a) * d)
			local drop = mk({ Size = V3(0.25, 1.6, 0.25), Position = pos, Color = GOLD })
			tween(drop, 0.35, { Position = pos - V3(0, 22, 0), Transparency = 0.6 }, Enum.EasingStyle.Linear)
			die(drop, 0.4)
		end)
	end
	each(allyRoots(c.d), function(r)
		risers(r, HEAL, 0.9, "+")
	end)
end

local function reviveAt(pos: Vector3)
	pillar(pos, GOLD, 24, 2.4, 1.2)
	ring(pos, 1, 9, Color3.fromRGB(255, 244, 200), 0.8, 0.4)
	for i = 1, 3 do
		task.delay(i * 0.15, function()
			ring(pos + V3(0, i * 2.5, 0), 3, 1, GOLD, 0.6, 0.25)
		end)
	end
	glyph(pos + V3(0, 3, 0), "✚", GOLD, 6, 56, 1.4)
	burst(pos + V3(0, 2, 0), GOLD, 20, 8, 0.5, 0.8, 1)
end

function A.cleansing_splash(c)
	prop(c.char, "flask", "R", GOLD, 0.5)
	pose(c.char, { r = { -140 }, t = 0.1, hold = 0.2 })
	each(c.d.fallen, reviveAt)
end

-- Rogue -----------------------------------------------------------------------
local CRIMSON = Color3.fromRGB(255, 90, 100)
local SHADOW = Color3.fromRGB(150, 110, 190)

local function bleedDrops(at: Vector3)
	for _ = 1, 6 do
		local s = mk({ Size = V3(0.3, 0.45, 0.3), Position = at + V3(rng:NextNumber(-1, 1), 2.5, rng:NextNumber(-1, 1)), Color = Color3.fromRGB(190, 30, 50), Shape = Enum.PartType.Ball })
		tween(s, 0.6, { Position = s.Position - V3(0, 3.5, 0), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		die(s, 0.7)
	end
end

local function cross(at: Vector3, color: Color3, size: number)
	for sign = -1, 1, 2 do
		local bar = mk({ Size = V3(0.3, 0.3, size), CFrame = CFrame.new(at) * CFrame.Angles(0, 0, rad(45 * sign)) * CFrame.Angles(0, rad(25), 0), Color = color })
		tween(bar, 0.3, { Transparency = 1, Size = V3(0.05, 0.05, size * 1.3) })
		die(bar, 0.35)
	end
end

function A.backstab(c)
	prop(c.char, "dagger", "R", CRIMSON, 0.5)
	pose(c.char, { r = { -100, 0, -30 }, t = 0.05, hold = 0.15 })
	local at = c.d.t and c.d.t[1]
	if at then
		task.delay(0.05, function()
			cross(at + V3(0, 2, 0), Color3.new(1, 1, 1), 5)
			spark(at + V3(0, 2, 0), CRIMSON, 3)
			bleedDrops(at)
		end)
	end
end

function A.fan_of_blades(c)
	prop(c.char, "dagger", "R", CRIMSON, 0.5)
	pose(c.char, { r = { -90 }, l = { -90 }, t = 0.06, hold = 0.2 })
	slash(c.root, { radius = 5, from = 0, to = 360, color = Color3.new(1, 1, 1), len = 5, dur = 0.28, width = 0.4 })
	slash(c.root, { radius = 4, from = 180, to = 540, color = CRIMSON, len = 4, dur = 0.28, width = 0.3 })
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		local dir = V3(math.cos(a), 0, math.sin(a))
		local blade = mk({ Size = V3(0.25, 0.25, 2.6), CFrame = CFrame.lookAt(c.root.Position + dir * 3, c.root.Position + dir * 10), Color = Color3.fromRGB(230, 235, 245), Material = Enum.Material.Metal })
		tween(blade, 0.3, { CFrame = CFrame.lookAt(c.root.Position + dir * 9, c.root.Position + dir * 16), Transparency = 1 }, Enum.EasingStyle.Linear)
		die(blade, 0.35)
	end
	each(c.d.t, function(p)
		cross(p + V3(0, 2, 0), Color3.new(1, 1, 1), 4)
	end)
end

function A.vanish(c)
	pose(c.char, { r = { -70, 0, -60 }, l = { -70, 0, 60 }, t = 0.08, hold = 0.4 })
	local at = c.root.Position
	ball(at, 3, 11, Color3.fromRGB(70, 56, 90), 0.8, 0.25).Material = Enum.Material.SmoothPlastic
	burst(at, SHADOW, 22, 7, 0.8, 0.8, 0.8, Enum.Material.SmoothPlastic)
	ring(at, 1, 6, SHADOW, 0.5)
end

function A.shadowstep(c)
	local from, to = c.d.from or c.d.o, c.d.to
	prop(c.char, "dagger", "R", CRIMSON, 0.5)
	pose(c.char, { r = { -100, 0, -30 }, t = 0.05, hold = 0.15 })
	if from then
		ball(from, 2, 8, Color3.fromRGB(70, 56, 90), 0.4, 0.2)
		burst(from, SHADOW, 12, 5, 0.6, 0.5, 0.6, Enum.Material.SmoothPlastic)
	end
	if from and to then
		local dist = (to - from).Magnitude
		local trail = mk({ Size = V3(1.4, 4, dist), CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -dist / 2), Color = Color3.fromRGB(60, 46, 80), Transparency = 0.3 })
		tween(trail, 0.4, { Transparency = 1, Size = V3(0.1, 4, dist) })
		die(trail, 0.45)
	end
	local at = c.d.t and c.d.t[1]
	if at then
		cross(at + V3(0, 2, 0), Color3.new(1, 1, 1), 5)
		spark(at + V3(0, 2, 0), CRIMSON, 3)
	end
end

function A.death_bloom(c)
	local r = math.max(c.d.r or 35, 10)
	prop(c.char, "dagger", "R", CRIMSON, 0.7)
	pose(c.char, { r = { -120 }, l = { -120 }, t = 0.1, hold = 0.3 })
	local at = c.root.Position
	for i = 1, 3 do
		slash(c.root, { radius = 4 + i * 2, from = (i - 1) * 120, to = (i - 1) * 120 + 360, color = i == 2 and CRIMSON or Color3.new(1, 1, 1), len = 6, dur = 0.35, width = 0.45, tilt = i * 12 })
	end
	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2
		local dir = V3(math.cos(a), 0, math.sin(a))
		local petal = mk({ Size = V3(0.5, 0.2, r * 0.55), CFrame = CFrame.lookAt(at + dir * 2, at + dir * 8) * CFrame.new(0, -1.6, -r * 0.27), Color = i % 2 == 0 and CRIMSON or Color3.fromRGB(120, 20, 50) })
		tween(petal, 0.7, { Transparency = 1, Size = V3(1.6, 0.1, r * 0.8) })
		die(petal, 0.8)
	end
	ring(at, 1, r, CRIMSON, 0.6, 0.35)
	each(c.d.t, function(p)
		cross(p + V3(0, 2, 0), Color3.new(1, 1, 1), 4)
		bleedDrops(p)
	end)
	AbilityFx.shake(0.4)
end

function A.execution(c)
	prop(c.char, "dagger", "R", CRIMSON, 0.6)
	pose(c.char, { r = { -170 }, t = 0.14, hold = 0.1, back = 0.25 })
	local at = c.d.t and c.d.t[1]
	task.delay(0.14, function()
		slash(c.root, { radius = 5, from = -70, to = 40, tilt = 90, color = CRIMSON, len = 7, dur = 0.14, width = 0.8, height = 3 })
		if at then
			cross(at + V3(0, 2, 0), CRIMSON, 7)
			spark(at + V3(0, 2, 0), CRIMSON, 6)
			bleedDrops(at)
		end
		AbilityFx.shake(0.55)
	end)
end

-- Druid -----------------------------------------------------------------------
local LEAF = Color3.fromRGB(110, 196, 155)

local function vines(at: Vector3, r: number, n: number)
	local y = groundY(at)
	for i = 1, n do
		local a, d = (i / n) * math.pi * 2, rng:NextNumber(0.2, 1) * r
		local base = V3(at.X + math.cos(a) * d, y, at.Z + math.sin(a) * d)
		local h = rng:NextNumber(3, 6)
		local vine = mk({ Size = V3(0.5, 0.5, 0.5), CFrame = CFrame.new(base) * CFrame.Angles(rad(rng:NextNumber(-20, 20)), 0, rad(rng:NextNumber(-20, 20))), Color = Color3.fromRGB(70, 140, 70), Material = Enum.Material.Grass })
		local cf = vine.CFrame
		tween(vine, 0.25, { Size = V3(0.5, h, 0.5), CFrame = cf * CFrame.new(0, h / 2, 0) })
		local thorn = mk({ Size = V3(0.3, 0.9, 0.3), CFrame = cf * CFrame.new(0.4, h * 0.6, 0) * CFrame.Angles(0, 0, rad(-60)), Color = Color3.fromRGB(200, 220, 120) })
		tween(thorn, 0.9, { Transparency = 1 }, Enum.EasingStyle.Linear)
		task.delay(0.8, function()
			if vine.Parent then
				tween(vine, 0.5, { Transparency = 1 })
			end
		end)
		die(vine, 1.4)
		die(thorn, 1)
	end
end

function A.briar_burst(c)
	prop(c.char, "wand", "R", LEAF, 0.5)
	pose(c.char, { r = { -100 }, t = 0.08, hold = 0.2 })
	local at = c.d.t and c.d.t[1]
	if at then
		local p = at + V3(0, 2, 0)
		projectile(handPos(c), p, Color3.fromRGB(150, 220, 110), 0.9, 160, nil, function()
			local r = c.d.r or 8
			ring(at, 1, r, LEAF, 0.5)
			vines(at, r, 12)
			burst(p, Color3.fromRGB(150, 220, 110), 10, r, 0.5, 0.5)
		end)
	end
end

function A.thornshot(c)
	prop(c.char, "wand", "R", LEAF, 0.4)
	pose(c.char, { r = { -100 }, t = 0.08, hold = 0.2 })
	local at = c.d.t and c.d.t[1]
	if at then
		local p = at + V3(0, 2, 0)
		projectile(handPos(c), p, Color3.fromRGB(160, 120, 70), 0.5, 230, Enum.PartType.Block, function()
			spark(p, Color3.fromRGB(150, 220, 110), 3)
			burst(p, Color3.fromRGB(110, 150, 70), 6, 3, 0.3, 0.3)
		end, 3.2)
	end
end

local function summonFx(c, color: Color3, extra)
	local at = c.d.o or c.root.Position
	prop(c.char, "wand", "R", color, 0.8)
	pose(c.char, { r = { -140 }, t = 0.1, hold = 0.4 })
	local spot = at + c.root.CFrame.LookVector * 5
	ring(spot, 1, 6, color, 0.7, 0.35, 0.1)
	ring(spot, 3, 1, Color3.new(1, 1, 1), 0.7, 0.3, 0.2)
	pillar(spot, color, 14, 1.6, 0.8)
	burst(spot, color, 20, 7, 0.6, 0.7, 1)
	if extra then
		extra(spot)
	end
end

function A.lightning_bird(c)
	summonFx(c, Color3.fromRGB(255, 240, 120), function(s)
		for _ = 1, 4 do
			zig(s + V3(0, 14, 0), s + V3(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)), Color3.fromRGB(255, 255, 190), 0.4, 0.3)
		end
	end)
end

function A.fire_wolf(c)
	summonFx(c, Color3.fromRGB(255, 130, 60), function(s)
		for i = 1, 8 do
			local a = (i / 8) * math.pi * 2
			local f = mk({ Shape = Enum.PartType.Ball, Size = V3(1.6, 2.4, 1.6), Position = s + V3(math.cos(a) * 3, 1, math.sin(a) * 3), Color = Color3.fromRGB(255, rng:NextInteger(90, 170), 40) })
			tween(f, 0.7, { Position = f.Position + V3(0, 4, 0), Transparency = 1, Size = V3(0.3, 0.3, 0.3) })
			die(f, 0.8)
		end
	end)
end

function A.ice_bear(c)
	summonFx(c, Color3.fromRGB(160, 225, 255), function(s)
		for i = 1, 6 do
			local a = (i / 6) * math.pi * 2
			local shard = mk({ Size = V3(0.8, 3.2, 0.8), CFrame = CFrame.new(s + V3(math.cos(a) * 3, 1.4, math.sin(a) * 3)) * CFrame.Angles(rad(rng:NextNumber(-20, 20)), 0, rad(rng:NextNumber(-20, 20))), Color = Color3.fromRGB(190, 235, 255), Material = Enum.Material.Glass, Transparency = 0.2 })
			tween(shard, 1, { Transparency = 1 }, Enum.EasingStyle.Linear)
			die(shard, 1.1)
		end
	end)
end

function A.nature_golem(c)
	summonFx(c, Color3.fromRGB(120, 200, 100), function(s)
		debris(s, 4, 8, Color3.fromRGB(110, 120, 90))
		cracks(s, 6, 8)
		AbilityFx.shake(0.3)
	end)
end

-- Bard -----------------------------------------------------------------------
local PINK = Color3.fromRGB(240, 149, 191)

local function notes(at: Vector3, n: number, spread: number, color: Color3?)
	local set = { "♪", "♫", "♩" }
	for i = 1, n do
		task.delay(i * 0.04, function()
			glyph(at + V3(rng:NextNumber(-spread, spread), rng:NextNumber(0, 2), rng:NextNumber(-spread, spread)), set[rng:NextInteger(1, 3)], color or PINK, 4, 34, 0.9)
		end)
	end
end

function A.discord_note(c)
	local r = math.max(c.d.r or 25, 8)
	prop(c.char, "lute", "L", PINK, 0.6)
	pose(c.char, { r = { -70, 0, 30 }, l = { -80 }, t = 0.07, hold = 0.2 })
	local at = c.root.Position
	for i = 1, 3 do
		task.delay((i - 1) * 0.1, function()
			ring(at, 2, r * (0.6 + i * 0.2), PINK, 0.5, 0.3, 0.2)
		end)
	end
	notes(at + V3(0, 2, 0), 8, r * 0.5)
	each(c.d.t, function(p)
		spark(p + V3(0, 2, 0), PINK, 3)
	end)
end

function A.quickstring(c)
	prop(c.char, "lute", "L", PINK, 0.5)
	pose(c.char, { r = { -70, 0, 30 }, l = { -90 }, t = 0.07, hold = 0.2 })
	local at = c.d.t and c.d.t[1]
	if at then
		local p = at + V3(0, 2, 0)
		projectile(handPos(c), p, PINK, 0.5, 260, Enum.PartType.Block, function()
			spark(p, PINK, 3)
		end, 3)
		glyph(handPos(c), "♪", PINK, 3, 34, 0.5)
	end
end

local function chordBuff(c, color: Color3, text: string)
	prop(c.char, "lute", "L", color, 0.8)
	pose(c.char, { r = { -70, 0, 30 }, l = { -90 }, t = 0.07, hold = 0.5 })
	ring(c.root.Position, 2, 16, color, 0.6, 0.35)
	each(allyRoots(c.d), function(r)
		ring(r.Position, 1, 5, color, 0.5)
		risers(r, color, 0.8, text)
	end)
end

function A.battle_anthem(c)
	chordBuff(c, Color3.fromRGB(255, 130, 110), "♪")
	banner(c, Color3.fromRGB(255, 130, 110))
	each(allyRoots(c.d), function(r)
		aura(r, Color3.fromRGB(255, 150, 120), c.d.duration or 8, "column")
	end)
end

function A.fleet_rhythm(c)
	chordBuff(c, Color3.fromRGB(190, 240, 255), "♫")
	each(allyRoots(c.d), function(r)
		windLines(r, Color3.fromRGB(210, 245, 255), 6)
	end)
end

function A.grand_crescendo(c)
	chordBuff(c, GOLD, "♬")
	for i = 1, 4 do
		task.delay((i - 1) * 0.12, function()
			ring(c.root.Position, 2, 12 + i * 8, GOLD, 0.7, 0.4, 0.15)
		end)
	end
	each(allyRoots(c.d), function(r)
		aura(r, GOLD, c.d.duration or 8, "column")
		pillar(r.Position, GOLD, 18, 1.6, 0.8)
	end)
	AbilityFx.shake(0.4)
end

function A.rallying_chord(c)
	chordBuff(c, HEAL, "♪")
	each(allyRoots(c.d), function(r)
		risers(r, HEAL, 0.8, "+")
	end)
end

-- Healer -----------------------------------------------------------------------

function A.life_spark(c)
	prop(c.char, "wand", "R", GOLD, 0.4)
	pose(c.char, { r = { -100 }, t = 0.07, hold = 0.2 })
	local at = c.d.t and c.d.t[1]
	if at then
		local p = at + V3(0, 2, 0)
		projectile(handPos(c), p, Color3.fromRGB(255, 250, 190), 0.8, 190, nil, function()
			spark(p, GOLD, 3.5)
		end)
	end
end

local function rayTo(c, root: BasePart, big: boolean)
	local a, b = handPos(c), root.Position + V3(0, 1, 0)
	local dist = (b - a).Magnitude
	local beam = mk({ Size = V3(big and 1.1 or 0.6, big and 1.1 or 0.6, dist), CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -dist / 2), Color = HEAL, Transparency = 0.25 })
	tween(beam, 0.6, { Transparency = 1, Size = V3(0.1, 0.1, dist) })
	die(beam, 0.7)
	ring(root.Position, 1, big and 6 or 4, HEAL, 0.5)
	risers(root, HEAL, big and 1 or 0.7, "+")
end

function A.healing_ray(c)
	prop(c.char, "wand", "R", HEAL, 0.7)
	pose(c.char, { r = { -100 }, t = 0.08, hold = 0.45 })
	each(allyRoots(c.d), function(r)
		rayTo(c, r, false)
	end)
end

function A.major_mend(c)
	prop(c.char, "wand", "R", HEAL, 0.9)
	pose(c.char, { r = { -120 }, l = { -60 }, t = 0.1, hold = 0.6 })
	each(allyRoots(c.d), function(r)
		rayTo(c, r, true)
		ball(r.Position, 2, 9, HEAL, 0.6, 0.45)
	end)
end

function A.quick_revival(c)
	prop(c.char, "wand", "R", GOLD, 0.7)
	pose(c.char, { r = { -140 }, t = 0.1, hold = 0.4 })
	each(c.d.fallen, reviveAt)
end

function A.miracle(c)
	pose(c.char, { r = { -170 }, l = { -170 }, t = 0.14, hold = 0.8 })
	local at = c.root.Position
	pillar(at, GOLD, 40, 5, 1.6)
	for i = 1, 4 do
		task.delay((i - 1) * 0.14, function()
			ring(at, 2, 12 + i * 7, i % 2 == 0 and HEAL or GOLD, 0.8, 0.4, 0.15)
		end)
	end
	each(allyRoots(c.d), function(r)
		pillar(r.Position, GOLD, 22, 1.8, 1)
		risers(r, HEAL, 1.2, "+")
	end)
	AbilityFx.shake(0.35)
end

function A.mass_revival(c)
	pose(c.char, { r = { -170 }, l = { -170 }, t = 0.14, hold = 0.8 })
	ring(c.root.Position, 2, 30, GOLD, 1, 0.4, 0.15)
	each(c.d.fallen, reviveAt)
	pillar(c.root.Position, GOLD, 30, 3, 1.2)
end

-- ------------------------------------------------------------------ entry

function AbilityFx.play(d)
	local char = charOf(d.caster)
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (char and root) then
		return
	end
	local colorHex = d.color
	local c = {
		d = d,
		char = char,
		root = root,
		color = colorHex or Color3.new(1, 1, 1),
	}
	local fn = A[d.id]
	if not fn then
		return
	end
	local ok, err = pcall(fn, c)
	if not ok then
		warn("[AbilityFx] " .. tostring(d.id) .. ": " .. tostring(err))
	end
end

AbilityFx.registered = A

return AbilityFx
