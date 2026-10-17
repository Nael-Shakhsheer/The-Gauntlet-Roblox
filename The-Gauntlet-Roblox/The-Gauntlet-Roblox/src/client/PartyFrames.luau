--!nonstrict
-- Party frames: one compact bar per other player (name, hero, level, health). Hidden when playing solo.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Kit = require(script.Parent.Kit)

local PartyFrames = {}
local player = Players.LocalPlayer
local holder
local rows = {} -- [Player] = { frame, name, fill, hp }

local function build(other: Player)
	local f = Kit.panel({ Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 0.15 }, holder)
	local name = Kit.text({ Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -16, 0, 16), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Font = Kit.BOLD }, f)
	local back = Kit.frame({ Position = UDim2.fromOffset(8, 22), Size = UDim2.new(1, -16, 0, 9), BackgroundColor3 = Kit.UI.bg }, f)
	local fill = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Kit.UI.mint }, back)
	rows[other] = { frame = f, name = name, fill = fill }
end

local function refresh()
	local seen = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			seen[other] = true
			local row = rows[other]
			if not row then
				build(other)
				row = rows[other]
			end
			local humanoid = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
			local ratio = humanoid and humanoid.MaxHealth > 0 and math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) or 0
			row.name.Text = ("%s  -  %s Lv %d"):format(other.DisplayName, other:GetAttribute("Hero") or "?", other:GetAttribute("Level") or 1)
			row.fill.Size = UDim2.fromScale(ratio, 1)
			row.fill.BackgroundColor3 = ratio > 0.5 and Kit.UI.mint or ratio > 0.25 and Kit.UI.gold or Kit.UI.red
		end
	end
	for other, row in rows do
		if not seen[other] then
			row.frame:Destroy()
			rows[other] = nil
		end
	end
	holder.Visible = next(rows) ~= nil
end

function PartyFrames.init(gui: ScreenGui)
	holder = Instance.new("Frame")
	holder.Name = "PartyFrames"
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.new(0, 12, 0, 222)
	holder.Size = UDim2.fromOffset(220, 170)
	holder.Visible = false
	holder.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = holder
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.2 then
			acc = 0
			refresh()
		end
	end)
end

return PartyFrames
