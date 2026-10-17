--!nonstrict
-- Client atmosphere: owns Lighting post-processing, Sky/Clouds and camera-following ambient particles.
-- Each art region (Palette.Regions) carries a profile; AreaChanged tweens everything to it.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared.Palette)

local Atmosphere = {}

local TIME = TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local atmosphere, bloom, cc, rays, sky, clouds, emitters, anchor
local current

local function child(class, name, parent)
	local o = parent:FindFirstChild(name)
	if not o then
		o = Instance.new(class)
		o.Name = name
		o.Parent = parent
	end
	return o
end

local function tween(object, props)
	TweenService:Create(object, TIME, props):Play()
end

-- ---------------------------------------------------------------- particles
local function emitter(name, props)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.LightInfluence = 0
	e.Rate = 0
	for k, v in props do
		e[k] = v
	end
	e.Parent = anchor
	return e
end

local function buildParticles()
	anchor = Instance.new("Part")
	anchor.Name = "AmbientAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(90, 24, 90)
	anchor.Parent = workspace
	local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
	local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
	emitters = {
		pollen = emitter("pollen", {
			Texture = SPARK, Color = ColorSequence.new(Color3.fromRGB(255, 244, 190)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(5, 9), Speed = NumberRange.new(0.4, 1.4), SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(1.2, 0.2, 0.6), LightEmission = 0.8, Rotation = NumberRange.new(0, 360),
		}),
		leaves = emitter("leaves", {
			Texture = SMOKE, Color = ColorSequence.new(Color3.fromRGB(150, 170, 70), Color3.fromRGB(190, 140, 60)),
			Size = NumberSequence.new(0.35), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.1), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(6, 10), Speed = NumberRange.new(1, 2.5), SpreadAngle = Vector2.new(30, 30),
			Acceleration = Vector3.new(3, -1.6, 1.4), RotSpeed = NumberRange.new(-120, 120), Rotation = NumberRange.new(0, 360),
		}),
		dust = emitter("dust", {
			Texture = SMOKE, Color = ColorSequence.new(Color3.fromRGB(230, 200, 150)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.4) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.85), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(5, 9), Speed = NumberRange.new(0.5, 1.6), SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(2.4, 0, 0.8), LightEmission = 0.1,
		}),
		spores = emitter("spores", {
			Texture = SPARK, Color = ColorSequence.new(Color3.fromRGB(120, 210, 255), Color3.fromRGB(160, 255, 200)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.5), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.1), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(6, 10), Speed = NumberRange.new(0.3, 1), SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, 0.4, 0), LightEmission = 1, Rotation = NumberRange.new(0, 360),
		}),
		snow = emitter("snow", {
			Texture = SPARK, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
			Size = NumberSequence.new(0.3), Transparency = NumberSequence.new(0.1),
			Lifetime = NumberRange.new(6, 8), Speed = NumberRange.new(2, 4), SpreadAngle = Vector2.new(20, 20),
			Acceleration = Vector3.new(2, -3, 1), LightEmission = 0.3, Rotation = NumberRange.new(0, 360),
		}),
	}
	local RATES = { pollen = 5, leaves = 1.2, dust = 4, spores = 7, snow = 38 }
	Atmosphere.rates = RATES
	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if camera then
			anchor.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 4, 0))
		end
	end)
end

local function setParticles(kind)
	for name, e in emitters do
		local on = (kind == name) or (kind == "pollen" and name == "leaves")
		e.Enabled = on
		e.Rate = on and Atmosphere.rates[name] or 0
	end
	-- emitters spawn across the anchor's top face; they need a surface to emit from
	anchor.Size = Vector3.new(90, 24, 90)
end

-- ------------------------------------------------------------------- setup
function Atmosphere.init()
	atmosphere = child("Atmosphere", "GauntletAtmosphere", Lighting)
	bloom = child("BloomEffect", "GauntletBloom", Lighting)
	cc = child("ColorCorrectionEffect", "GauntletColor", Lighting)
	rays = child("SunRaysEffect", "GauntletRays", Lighting)
	sky = child("Sky", "GauntletSky", Lighting)
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 8
	sky.StarCount = 2500
	local terrain = workspace:WaitForChild("Terrain")
	clouds = child("Clouds", "GauntletClouds", terrain)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.ShadowSoftness = 0.3
	Lighting.ExposureCompensation = 0.1
	buildParticles()
	Atmosphere.apply("woodland", true)
end

function Atmosphere.apply(regionName: string, instant: boolean?)
	local r = Palette.Regions[regionName] or Palette.Regions.woodland
	if current == r and not instant then
		return
	end
	current = r
	local function go(object, props)
		if instant then
			for k, v in props do
				object[k] = v
			end
		else
			tween(object, props)
		end
	end
	go(Lighting, {
		Ambient = r.ambient, OutdoorAmbient = r.outdoor, Brightness = r.brightness, ClockTime = r.clock,
		FogColor = r.fog, FogStart = 120, FogEnd = regionName == "cavern" and 240 or 1100,
	})
	go(atmosphere, { Density = r.atmo.density, Offset = r.atmo.offset, Color = r.atmo.color, Decay = r.atmo.decay, Glare = r.atmo.glare, Haze = r.atmo.haze })
	go(bloom, { Intensity = r.bloom.intensity, Size = r.bloom.size, Threshold = r.bloom.threshold })
	go(cc, { Brightness = r.cc.brightness, Contrast = r.cc.contrast, Saturation = r.cc.saturation, TintColor = r.cc.tint })
	go(rays, { Intensity = r.sun.intensity, Spread = r.sun.spread })
	go(clouds, { Cover = r.clouds.cover, Density = r.clouds.density, Color = r.clouds.color })
	setParticles(r.particles)
end

return Atmosphere
