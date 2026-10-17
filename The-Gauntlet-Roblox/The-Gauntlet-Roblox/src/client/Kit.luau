--!nonstrict
-- Shared UI toolkit: theme, fonts and widget constructors so every panel has the same look
-- (rounded corners, soft strokes, readable font, hover feedback).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Palette = require(ReplicatedStorage:WaitForChild("Shared").Palette)

local Kit = {}
Kit.UI = Palette.UI
Kit.BODY = Enum.Font.GothamMedium
Kit.BOLD = Enum.Font.GothamBold
Kit.TITLE = Enum.Font.Antique
Kit.RADIUS = 6

Kit.RARITY = {
	Common = Color3.fromRGB(230, 226, 205),
	Uncommon = Color3.fromRGB(150, 220, 120),
	Rare = Color3.fromRGB(110, 170, 255),
	Epic = Color3.fromRGB(200, 140, 255),
	Legendary = Color3.fromRGB(255, 184, 70),
	Mythic = Color3.fromRGB(255, 96, 120),
}

function Kit.corner(parent: Instance, radius: number?): UICorner
	local existing = parent:FindFirstChildOfClass("UICorner")
	if existing then
		return existing
	end
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Kit.RADIUS)
	c.Parent = parent
	return c
end

function Kit.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Kit.UI.line
	s.Thickness = thickness or 1.5
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	if parent:IsA("GuiObject") and parent.BackgroundTransparency < 1 then
		Kit.corner(parent)
	end
	return s
end

function Kit.frame(props, parent: Instance?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in props do
		f[k] = v
	end
	f.Parent = parent
	if f.BackgroundTransparency < 1 and not props.NoCorner then
		Kit.corner(f)
	end
	return f
end

function Kit.text(props, parent: Instance?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Kit.BODY
	t.TextColor3 = Kit.UI.ink
	t.TextSize = 16
	for k, v in props do
		t[k] = v
	end
	t.Parent = parent
	return t
end

function Kit.button(props, parent: Instance?): TextButton
	local b = Instance.new("TextButton")
	b.Font = Kit.BODY
	b.TextSize = 16
	b.TextColor3 = Kit.UI.ink
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	for k, v in props do
		b[k] = v
	end
	b.Parent = parent
	Kit.corner(b)
	return b
end

-- Dark panel with a gold hairline and a soft vertical gradient.
function Kit.panel(props, parent: Instance?): Frame
	props.BackgroundColor3 = props.BackgroundColor3 or Kit.UI.panel
	local f = Kit.frame(props, parent)
	Kit.stroke(f, Kit.UI.line, 1.5)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	g.Parent = f
	return f
end

function Kit.tween(object: Instance, seconds: number, props, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

return Kit
