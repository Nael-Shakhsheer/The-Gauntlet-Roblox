--!nonstrict
-- Client-side life for welded rigs (see shared/Rig.luau): enemies walk-cycle and bob, villagers breathe,
-- sway their arms and turn to face you when you are close. Only Weld.C0 and the local pose of anchored
-- NPC roots are touched, so none of this replicates and the server pays nothing.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Life = {}

local player = Players.LocalPlayer
local ACTIVE_STUDS = 110 -- farther rigs are left in their rest pose
local FACE_STUDS = 22

local rigs = {} -- [Model] = rig record

local function collect(model: Model, root: BasePart)
	local limbs = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Weld") and d.Name == "Rig" and d.Part1 then
			local name = d.Part1.Name
			local kind = name:match("^(%a+)_")
			local sign = name:sub(-1) == "A" and 1 or name:sub(-1) == "B" and -1 or 0
			table.insert(limbs, {
				weld = d,
				base = d.C0,
				kind = kind, -- "Leg" | "Arm" | nil
				sign = sign,
				half = d.Part1.Size.Y / 2,
				flat = d.Part1.Size.X > d.Part1.Size.Y * 2, -- spider legs lie sideways
			})
		end
	end
	return { model = model, root = root, limbs = limbs, last = root.Position, phase = math.random() * 6, speed = 0, home = nil, offset = math.random() * 10 }
end

local function register(model: Instance)
	if rigs[model] or not model:IsA("Model") then
		return
	end
	local root = model.PrimaryPart or model:FindFirstChild("Torso") or model:FindFirstChild("Root")
	if not root then
		return
	end
	rigs[model] = collect(model, root)
	model.Destroying:Once(function()
		rigs[model] = nil
	end)
end

local function step(rig, dt: number, now: number, cameraPos: Vector3, myPos: Vector3?)
	local root = rig.root
	if not root.Parent then
		return
	end
	local pos = root.Position
	-- Anchored rigs are moved by the server in discrete steps, so measure speed between *changes*
	-- of position rather than per frame, and let it decay when nothing moves.
	local moved = (pos - rig.last) * Vector3.new(1, 0, 1)
	if moved.Magnitude > 0.02 then
		local elapsed = math.max(now - (rig.lastChange or now - 0.1), 0.016)
		local measured = moved.Magnitude / elapsed
		rig.lastChange = now
		rig.last = pos
		if measured < 60 then -- ignore teleports / knockback spikes
			rig.target = measured
		end
	elseif now - (rig.lastChange or 0) > 0.4 then
		rig.target = 0
	end
	rig.speed += ((rig.target or 0) - rig.speed) * math.min(1, dt * 6)
	local moving = math.clamp(rig.speed / 9, 0, 1)
	rig.phase += dt * (3 + rig.speed * 0.45) * (moving > 0.05 and 1 or 0.25)
	local swing = math.sin(rig.phase) * 0.75 * moving
	local bob = (math.sin(now * 2 + rig.offset) * 0.06 + math.abs(math.sin(rig.phase)) * 0.14 * moving)
	for _, limb in rig.limbs do
		local c0 = limb.base
		if limb.kind == "Leg" then
			if limb.flat then
				c0 = c0 * CFrame.Angles(0, limb.sign * swing * 0.5, 0)
			else
				c0 = c0 * CFrame.new(0, limb.half, 0) * CFrame.Angles(limb.sign * swing, 0, 0) * CFrame.new(0, -limb.half, 0)
			end
		elseif limb.kind == "Arm" then
			local idle = math.sin(now * 1.6 + rig.offset + limb.sign) * 0.07
			c0 = c0 * CFrame.new(0, limb.half * 0.9, 0) * CFrame.Angles(-limb.sign * swing * 0.8 + idle, 0, 0) * CFrame.new(0, -limb.half * 0.9, 0)
		else
			c0 = c0 + Vector3.new(0, bob, 0)
		end
		limb.weld.C0 = c0
	end
end

local function faceNpc(rig, dt: number, myPos: Vector3?)
	local root = rig.root
	rig.home = rig.home or root.CFrame
	local target = rig.home
	if myPos then
		local flat = Vector3.new(myPos.X, root.Position.Y, myPos.Z)
		if (flat - root.Position).Magnitude < FACE_STUDS then
			target = CFrame.lookAt(root.Position, flat)
		end
	end
	local alpha = math.min(1, dt * 4)
	root.CFrame = root.CFrame:Lerp(target, alpha)
end

function Life.init()
	local enemies = workspace:WaitForChild("Enemies", 30)
	if enemies then
		for _, m in enemies:GetChildren() do
			register(m)
		end
		enemies.ChildAdded:Connect(function(m)
			task.defer(register, m)
		end)
	end
	for _, m in CollectionService:GetTagged("Npc") do
		register(m)
	end
	CollectionService:GetInstanceAddedSignal("Npc"):Connect(function(m)
		task.defer(register, m)
	end)

	RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local cameraPos = camera.CFrame.Position
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local myPos = rootPart and rootPart.Position
		local now = os.clock()
		for model, rig in rigs do
			if not model.Parent then
				rigs[model] = nil
			elseif (rig.root.Position - cameraPos).Magnitude < ACTIVE_STUDS then
				step(rig, dt, now, cameraPos, myPos)
				if CollectionService:HasTag(model, "Npc") then
					faceNpc(rig, dt, myPos)
				end
			end
		end
	end)
end

return Life
