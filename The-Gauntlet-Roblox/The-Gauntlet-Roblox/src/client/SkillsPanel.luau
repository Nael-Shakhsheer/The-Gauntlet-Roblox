--!nonstrict
-- Skill tree window (K). Three branch columns of nodes; select a node, press Train. Respec is free in hubs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = require(Shared.Data)
local Palette = require(Shared.Palette)
local Remotes = require(Shared.Remotes)

local UI = Palette.UI
local SkillsPanel = {}
SkillsPanel.state = nil -- last SkillsState payload
SkillsPanel.onState = nil -- function(state), set by Main (hotbar locks)

local root, columns, header, detail, trainButton, respecButton
local selected -- node id
local hero

local function make(class, props, parent)
	local o = Instance.new(class)
	if o:IsA("GuiObject") then
		o.BorderSizePixel = 0
	end
	for k, v in props do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function label(props, parent)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.Code
	props.TextColor3 = props.TextColor3 or UI.ink
	props.TextSize = props.TextSize or 14
	return make("TextLabel", props, parent)
end

local function stroke(parent, color, thickness)
	return make("UIStroke", { Color = color or UI.line, Thickness = thickness or 1 }, parent)
end

local function nodeFor(id)
	for _, node in Data.HeroSkills.TREES[hero] or {} do
		if node.id == id then
			return node
		end
	end
	return nil
end

local function isBase(node)
	if node.type == "modifier" then
		return true
	end
	for _, a in Data.Abilities.sets[hero] do
		if a.id == node.id then
			return true
		end
	end
	return false
end

local function status(node, state)
	local r = state.ranks[node.id] or 0
	if node.starter then
		return "starter"
	end
	if r >= node.maxRank then
		return "owned"
	end
	if not isBase(node) then
		return "soon"
	end
	for _, req in node.requires do
		if not state.unlocked[req] then
			return "locked"
		end
	end
	return state.points >= node.cost and "ready" or "short"
end

local COLORS = {
	starter = UI.mint,
	owned = UI.mint,
	ready = UI.gold,
	short = UI.ink,
	locked = UI.muted,
	soon = UI.muted,
}

local function showDetail(state)
	local node = selected and nodeFor(selected)
	if not node then
		detail.Text = "Select a skill."
		trainButton.Visible = false
		return
	end
	local r = state.ranks[node.id] or 0
	local st = status(node, state)
	local lines = { ("%s  (%s%s)"):format(node.name, node.type, node.maxRank > 1 and (" rank %d/%d"):format(r, node.maxRank) or "") }
	local effect = node.effects[math.min(math.max(r, 1), #node.effects)]
	if node.maxRank > 1 and r < node.maxRank then
		effect = node.effects[r + 1]
	end
	table.insert(lines, effect or "")
	if #node.requires > 0 then
		local names = {}
		for _, req in node.requires do
			local p = nodeFor(req)
			table.insert(names, p and p.name or req)
		end
		table.insert(lines, "Requires: " .. table.concat(names, ", "))
	end
	local note = ({
		starter = "Known from the start.",
		owned = "Fully trained.",
		ready = ("Cost: %d point(s)."):format(node.cost),
		short = ("Cost: %d point(s). Not enough points."):format(node.cost),
		locked = "Train the prerequisite first.",
		soon = "Arrives in a later update.",
	})[st]
	table.insert(lines, note)
	detail.Text = table.concat(lines, "\n")
	trainButton.Visible = st == "ready"
	trainButton.Text = ("Train (%d)"):format(node.cost)
end

local function rebuild()
	local state = SkillsPanel.state
	if not state or not root then
		return
	end
	hero = state.hero
	local tree = Data.HeroSkills.TREES[hero]
	if not tree then
		return
	end
	for _, c in columns:GetChildren() do
		c:Destroy()
	end
	header.Text = ("%s skills    Points: %d  (earned %d)%s"):format(hero, state.points, state.earned, state.hub and "" or "    [change skills in Oakvale / Dunmere]")
	respecButton.Visible = state.hub ~= nil
	local order, seen = {}, {}
	for _, node in tree do
		if not seen[node.branch] then
			seen[node.branch] = true
			table.insert(order, node.branch)
		end
	end
	local width = 1 / math.max(#order, 1)
	for i, branch in order do
		local col = make("Frame", {
			Position = UDim2.fromScale((i - 1) * width, 0),
			Size = UDim2.new(width, -6, 1, 0),
			BackgroundColor3 = UI.panel,
			BackgroundTransparency = 0.3,
		}, columns)
		label({ Size = UDim2.new(1, 0, 0, 22), Text = branch, TextColor3 = UI.gold, TextSize = 15 }, col)
		local list = make("Frame", { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 1, -24), BackgroundTransparency = 1 }, col)
		make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		local n = 0
		for _, node in tree do
			if node.branch == branch then
				n += 1
				local st = status(node, state)
				local r = state.ranks[node.id] or 0
				local b = make("TextButton", {
					Size = UDim2.new(1, -8, 0, 30),
					LayoutOrder = n + (node.type == "ability" and 0 or node.type == "modifier" and 20 or 40),
					BackgroundColor3 = node.id == selected and Color3.fromRGB(70, 60, 40) or Color3.fromRGB(34, 30, 26),
					AutoButtonColor = true,
					Font = Enum.Font.Code,
					TextSize = 13,
					TextColor3 = COLORS[st],
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = ("  %s%s"):format(node.name, node.maxRank > 1 and ("  %d/%d"):format(r, node.maxRank) or ""),
				}, list)
				stroke(b, COLORS[st], node.id == selected and 2 or 1)
				label({
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -4, 0.5, 0),
					Size = UDim2.fromOffset(60, 14),
					Text = (st == "soon" and "soon") or (st == "starter" and "free") or (st == "owned" and "owned") or (node.cost .. "pt"),
					TextSize = 11,
					TextColor3 = COLORS[st],
					TextXAlignment = Enum.TextXAlignment.Right,
				}, b)
				b.Activated:Connect(function()
					selected = node.id
					rebuild()
				end)
			end
		end
	end
	showDetail(state)
end

function SkillsPanel.close()
	if root then
		root.Visible = false
	end
end

SkillsPanel.onOpen = nil -- set by Main: closes the other windows

function SkillsPanel.toggle()
	if root then
		root.Visible = not root.Visible
		if root.Visible then
			if SkillsPanel.onOpen then
				SkillsPanel.onOpen()
			end
			Remotes.get("Skills"):FireServer("sync") -- the server answers with a fresh SkillsState
			if not SkillsPanel.state then
				header.Text = "Loading skills..."
			end
			rebuild()
		end
	end
end

function SkillsPanel.visible()
	return root and root.Visible
end

function SkillsPanel.init(gui: ScreenGui)
	root = make("Frame", {
		Name = "SkillsPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(780, 500),
		BackgroundColor3 = UI.panel,
		Visible = false,
		ZIndex = 20,
	}, gui)
	stroke(root, UI.gold, 2)
	header = label({ Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -150, 0, 24), Text = "", TextSize = 16, TextColor3 = UI.gold, TextXAlignment = Enum.TextXAlignment.Left }, root)
	local close = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(60, 24),
		BackgroundColor3 = Color3.fromRGB(80, 40, 36),
		Font = Enum.Font.Code,
		TextSize = 14,
		TextColor3 = UI.ink,
		Text = "Close",
	}, root)
	close.Activated:Connect(function()
		root.Visible = false
	end)
	respecButton = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -74, 0, 6),
		Size = UDim2.fromOffset(60, 24),
		BackgroundColor3 = Color3.fromRGB(50, 50, 60),
		Font = Enum.Font.Code,
		TextSize = 14,
		TextColor3 = UI.ink,
		Text = "Respec",
	}, root)
	respecButton.Activated:Connect(function()
		selected = nil
		Remotes.get("Skills"):FireServer("respec")
	end)
	columns = make("Frame", { Position = UDim2.fromOffset(10, 36), Size = UDim2.new(1, -20, 1, -150), BackgroundTransparency = 1 }, root)
	detail = label({
		Position = UDim2.new(0, 10, 1, -106),
		Size = UDim2.new(1, -150, 0, 98),
		Text = "Select a skill.",
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, root)
	trainButton = make("TextButton", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -14),
		Size = UDim2.fromOffset(120, 36),
		BackgroundColor3 = Color3.fromRGB(60, 90, 50),
		Font = Enum.Font.Code,
		TextSize = 16,
		TextColor3 = UI.ink,
		Text = "Train",
		Visible = false,
	}, root)
	trainButton.Activated:Connect(function()
		if selected then
			Remotes.get("Skills"):FireServer("unlock", selected)
		end
	end)

	Remotes.get("SkillsState").OnClientEvent:Connect(function(state)
		SkillsPanel.state = state
		if root.Visible then
			rebuild()
		end
		if SkillsPanel.onState then
			SkillsPanel.onState(state)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.K then
			SkillsPanel.toggle()
		end
	end)
end

return SkillsPanel
