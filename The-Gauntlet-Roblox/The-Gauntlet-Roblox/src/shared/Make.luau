--!nonstrict
-- Small helpers for building the blocky, pixel-art-inspired 3D look.
local Make = {}

-- Anchored, flat-shaded block. props: any Part property (Size, CFrame, Color...).
function Make.part(props, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CastShadow = true
	p.CanTouch = false -- nothing in the port uses Touched; saves physics work
	for key, value in props do
		p[key] = value
	end
	p.Parent = parent
	return p
end

-- Decoration that never blocks movement or raycasts.
function Make.decor(props, parent: Instance?): Part
	local p = Make.part(props, parent)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false -- decor never needs to cast shadows
	return p
end

function Make.shade(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + amount, 0, 1))
end

function Make.label(adornee: Instance, text: string, color: Color3, offsetY: number, width: number?, maxDistance: number?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width or 180, 26)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance or 48
	gui.Adornee = adornee
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.25
	t.Font = Enum.Font.GothamMedium
	t.TextScaled = false
	t.TextSize = 15
	t.Name = "Text"
	t.Parent = gui
	gui.Parent = adornee
	return gui
end

return Make
