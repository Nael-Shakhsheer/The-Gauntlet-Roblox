--!nonstrict
-- Distant scenery outside the playable world: a ring of low-poly stepped mountains and hills so the
-- horizon has depth instead of an empty fog edge. Decor only (no collision, no queries).
local Make = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Make)

local Backdrop = {}

local function mountain(parent: Instance, at: Vector3, radius: number, height: number, color: Color3, rng: Random)
	local tiers = 4
	for i = 1, tiers do
		local k = 1 - (i - 1) / tiers
		local d = radius * 2 * k
		local h = height / tiers
		local disc = Make.decor({
			Size = Vector3.new(h * 1.05, d, d * (0.85 + rng:NextNumber() * 0.2)),
			Color = Make.shade(color, (i - 1) * 0.04),
			Material = Enum.Material.Slate,
		}, parent)
		disc.Shape = Enum.PartType.Cylinder
		disc.CFrame = CFrame.new(at + Vector3.new(0, (i - 0.5) * h - 4, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi, math.pi / 2)
		disc.CastShadow = false
	end
	-- snowy cap on the tall ones
	if height > 150 then
		local cap = Make.decor({ Size = Vector3.new(height / tiers * 0.7, radius * 0.5, radius * 0.5), Color = Color3.fromRGB(235, 240, 246), Material = Enum.Material.Snow }, parent)
		cap.Shape = Enum.PartType.Cylinder
		cap.CFrame = CFrame.new(at + Vector3.new(0, height - 4 + height / tiers * 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		cap.CastShadow = false
	end
end

-- bounds = { minX, maxX, minZ, maxZ } of the walkable world (studs).
function Backdrop.build(bounds)
	local folder = Instance.new("Folder")
	folder.Name = "Backdrop"
	folder.Parent = workspace
	local rng = Random.new(4242)
	local cx, cz = (bounds.minX + bounds.maxX) / 2, (bounds.minZ + bounds.maxZ) / 2
	local rx, rz = (bounds.maxX - bounds.minX) / 2 + 450, (bounds.maxZ - bounds.minZ) / 2 + 450
	local count = 34
	for i = 1, count do
		local a = i / count * math.pi * 2 + rng:NextNumber() * 0.08
		local jitter = 1 + rng:NextNumber() * 0.25
		local at = Vector3.new(cx + math.cos(a) * rx * jitter, 0, cz + math.sin(a) * rz * jitter)
		local tall = rng:NextNumber() < 0.45
		local radius = (tall and 150 or 210) * (0.8 + rng:NextNumber() * 0.5)
		local height = tall and 150 + rng:NextNumber() * 130 or 45 + rng:NextNumber() * 55
		local tone = tall and Color3.fromRGB(104, 118, 128) or Color3.fromRGB(84, 108, 84)
		mountain(folder, at, radius, height, tone, rng)
	end
	-- ground skirt so the horizon below the mountains is not the void
	local skirt = Make.decor({
		Name = "Skirt",
		Size = Vector3.new((rx + 900) * 2, 4, (rz + 900) * 2),
		Position = Vector3.new(cx, -2.4, cz),
		Color = Color3.fromRGB(88, 104, 66),
		Material = Enum.Material.Grass,
	}, folder)
	skirt.CastShadow = false
end

return Backdrop
