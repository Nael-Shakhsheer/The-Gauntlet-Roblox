--!nonstrict
-- Inventory window (I): three equipment slots, a 6x4 bag, an item card with a comparison against what you wear.
-- All changes are requests to the server (Inventory remote); this file only renders the state it sends back.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gear = require(Shared.Gear)
local Remotes = require(Shared.Remotes)
local Kit = require(script.Parent.Kit)

local UI = Kit.UI
local InventoryPanel = {}
InventoryPanel.state = nil

local COLS, ROWS, CELL, GAP = 6, 4, 56, 6
local SLOT_ORDER = { { "w", "Weapon" }, { "a", "Armor" }, { "t", "Trinket" } }
local FIELD = { w = "weapon", a = "armor", t = "trinket" }
local GLYPH = { w = "W", a = "A", t = "T" }

local root, grid, equipRow, card, runesLabel, countLabel, summary
local selected -- { kind = "bag"|"eq", index = n | key = "w" }
local cells = {}
local eqCells = {}

local function color(inst)
	local rgb = Gear.rgb(inst)
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function send(action, arg)
	Remotes.get("Inventory"):FireServer(action, arg)
end

local function selectedItem()
	local s = InventoryPanel.state
	if not s or not selected then
		return nil
	end
	if selected.kind == "bag" then
		return s.bag[selected.index]
	end
	return s[FIELD[selected.key]]
end

local function paintCell(cell, inst)
	local stroke = cell:FindFirstChildOfClass("UIStroke")
	local glyph = cell:FindFirstChild("Glyph")
	local lvl = cell:FindFirstChild("Lvl")
	if inst then
		local c = color(inst)
		stroke.Color = c
		stroke.Thickness = 2
		glyph.Text = GLYPH[Gear.slotOf(inst)]
		glyph.TextColor3 = c
		lvl.Text = tostring(Gear.itemLevel(inst))
	else
		stroke.Color = UI.line
		stroke.Thickness = 1
		glyph.Text = ""
		lvl.Text = ""
	end
end

local function line(parent, text, c, order, size)
	return Kit.text({
		Size = UDim2.new(1, 0, 0, size or 18),
		Text = text,
		TextColor3 = c or UI.ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		LayoutOrder = order,
		TextWrapped = true,
	}, parent)
end

local function delta(label, a, b, order, parent, pct)
	local d = a - b
	if math.abs(d) < 0.005 then
		return
	end
	local sign = d > 0 and "+" or ""
	local text = pct and ("%s%.1f%% %s"):format(sign, d * 100, label) or ("%s%.1f %s"):format(sign, d, label)
	line(parent, text, d > 0 and Color3.fromRGB(130, 220, 130) or Color3.fromRGB(240, 120, 110), order)
end

local function renderCard()
	for _, child in card:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local inst = selectedItem()
	if not InventoryPanel.state then
		line(card, "Loading...", UI.muted, 1)
		return
	end
	if not inst then
		line(card, "Select an item.", UI.muted, 1)
		line(card, "Walk over drops to pick them up. Upgrades equip themselves.", UI.muted, 2, 40)
		return
	end
	local s = InventoryPanel.state
	local info = Gear.describe(inst)
	local c = color(inst)
	Kit.text({ Size = UDim2.new(1, 0, 0, 40), Text = info.name, TextColor3 = c, Font = Kit.BOLD, TextSize = 17, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 }, card)
	line(card, ("%s %s  -  item level %d"):format(info.rarity, info.slot, info.ilvl), UI.muted, 2)
	local ok = s.level >= info.levelReq and Gear.usableBy(inst, s.hero)
	if info.hero then
		line(card, "Class: " .. info.hero, Gear.usableBy(inst, s.hero) and UI.ink or Color3.fromRGB(240, 120, 110), 3)
	end
	line(card, "Requires level " .. info.levelReq, s.level >= info.levelReq and UI.ink or Color3.fromRGB(240, 120, 110), 4)
	if info.damage > 0 then
		line(card, ("Damage  %.1f"):format(info.damage), UI.ink, 5)
	end
	if info.armor > 0 then
		line(card, ("Armor  %.1f"):format(info.armor), UI.ink, 5)
	end
	for i, text in info.lines do
		line(card, text, c, 10 + i)
	end
	if info.effect then
		line(card, info.effect, UI.muted, 30)
	end
	if selected.kind == "bag" then
		local worn = s[FIELD[info.slotKey]]
		if worn then
			line(card, "vs equipped:", UI.muted, 40)
			local a, b = info.stats, Gear.stats(worn)
			delta("damage", a.damage, b.damage, 41, card)
			delta("armor", a.armor, b.armor, 42, card)
			for i, key in { "dmg", "crit", "leech", "ult", "hp", "speed", "xp" } do
				delta(Gear.AFFIXES[key][3], a[key], b[key], 43 + i, card, true)
			end
			delta("mana", a.mana, b.mana, 60, card)
		end
	end
	line(card, ("Sells for %d runes"):format(info.sell), UI.muted, 70)

	local bar = Kit.frame({ Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 80 }, card)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.Parent = bar
	if selected.kind == "bag" then
		local equip = Kit.button({ Size = UDim2.new(0.5, -3, 1, 0), Text = "Equip", BackgroundColor3 = ok and UI.gold or UI.line, TextColor3 = Color3.fromRGB(30, 22, 10), Font = Kit.BOLD }, bar)
		equip.Activated:Connect(function()
			send("equip", selected.index)
			selected = nil
		end)
		local sell = Kit.button({ Size = UDim2.new(0.5, -3, 1, 0), Text = "Sell", BackgroundColor3 = UI.panel }, bar)
		Kit.stroke(sell, UI.line, 1)
		sell.Activated:Connect(function()
			send("sell", selected.index)
			selected = nil
		end)
	else
		local un = Kit.button({ Size = UDim2.fromScale(1, 1), Text = "Unequip", BackgroundColor3 = UI.panel }, bar)
		Kit.stroke(un, UI.line, 1)
		un.Activated:Connect(function()
			send("unequip", selected.key)
			selected = nil
		end)
	end
end

local function renderSummary(s)
	local total = Gear.stats(nil)
	for _, key in { "weapon", "armor", "trinket" } do
		if s[key] then
			for k, v in Gear.stats(s[key]) do
				total[k] += v
			end
		end
	end
	local parts = { ("Damage +%.1f"):format(total.damage), ("Armor %.1f"):format(total.armor) }
	for _, key in { "dmg", "crit", "leech", "ult", "hp", "speed", "xp" } do
		if total[key] > 0 then
			table.insert(parts, ("%s +%.1f%%"):format(Gear.AFFIXES[key][3], total[key] * 100))
		end
	end
	if total.mana > 0 then
		table.insert(parts, ("Mana +%d"):format(total.mana))
	end
	summary.Text = table.concat(parts, "   ")
end

local function render()
	local s = InventoryPanel.state
	if not root then
		return
	end
	if not s then
		renderCard()
		return
	end
	for i, cell in cells do
		paintCell(cell, s.bag[i])
		cell.BackgroundColor3 = (selected and selected.kind == "bag" and selected.index == i) and UI.line or UI.panel
	end
	for key, cell in eqCells do
		paintCell(cell, s[FIELD[key]])
		cell.BackgroundColor3 = (selected and selected.kind == "eq" and selected.key == key) and UI.line or UI.panel
	end
	runesLabel.Text = ("Runes %d"):format(s.runes)
	countLabel.Text = ("Bag %d/%d"):format(#s.bag, s.size)
	renderSummary(s)
	renderCard()
end

local function makeCell(parent, onClick)
	local cell = Kit.button({ Size = UDim2.fromOffset(CELL, CELL), Text = "", BackgroundColor3 = UI.panel }, parent)
	Kit.stroke(cell, UI.line, 1)
	Kit.text({ Name = "Glyph", Size = UDim2.fromScale(1, 1), Text = "", Font = Kit.BOLD, TextSize = 26 }, cell)
	Kit.text({ Name = "Lvl", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -4, 1, -2), Size = UDim2.fromOffset(24, 14), Text = "", TextSize = 11, TextColor3 = UI.muted, TextXAlignment = Enum.TextXAlignment.Right }, cell)
	cell.Activated:Connect(onClick)
	return cell
end

function InventoryPanel.visible(): boolean
	return root ~= nil and root.Visible
end

function InventoryPanel.close()
	if root then
		root.Visible = false
	end
end

InventoryPanel.onOpen = nil -- set by Main: closes the other windows

function InventoryPanel.toggle()
	if not root then
		return
	end
	root.Visible = not root.Visible
	if root.Visible then
		if InventoryPanel.onOpen then
			InventoryPanel.onOpen()
		end
		send("sync")
		render()
	end
end

function InventoryPanel.init(gui: ScreenGui)
	local width = COLS * (CELL + GAP) + 24 + 250 + 24
	root = Kit.panel({
		Name = "Inventory",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, 470),
		Visible = false,
		ZIndex = 30,
	}, gui)
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local function fit()
		local view = gui.AbsoluteSize
		scale.Scale = math.clamp(math.min(view.X / (width + 20), view.Y / 490), 0.55, 1)
	end
	fit()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	Kit.text({ Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(200, 30), Text = "Inventory", Font = Kit.TITLE, TextSize = 24, TextColor3 = UI.gold, TextXAlignment = Enum.TextXAlignment.Left }, root)
	local close = Kit.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(30, 28), Text = "X", BackgroundColor3 = UI.panel }, root)
	close.Activated:Connect(InventoryPanel.toggle)

	-- equipment row
	equipRow = Kit.frame({ Position = UDim2.fromOffset(16, 44), Size = UDim2.fromOffset(3 * (CELL + GAP + 36), CELL + 16), BackgroundTransparency = 1 }, root)
	local eqLayout = Instance.new("UIListLayout")
	eqLayout.FillDirection = Enum.FillDirection.Horizontal
	eqLayout.Padding = UDim.new(0, 8)
	eqLayout.Parent = equipRow
	for _, entry in SLOT_ORDER do
		local key = entry[1]
		local wrap = Kit.frame({ Size = UDim2.fromOffset(CELL + 30, CELL + 16), BackgroundTransparency = 1 }, equipRow)
		local cell = makeCell(wrap, function()
			selected = { kind = "eq", key = key }
			render()
		end)
		cell.Position = UDim2.fromOffset(0, 14)
		Kit.text({ Size = UDim2.fromOffset(CELL, 14), Text = entry[2], TextSize = 11, TextColor3 = UI.muted }, wrap)
		eqCells[key] = cell
	end

	summary = Kit.text({ Position = UDim2.fromOffset(16, 118), Size = UDim2.fromOffset(COLS * (CELL + GAP), 40), Text = "", TextSize = 12, TextColor3 = UI.muted, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, root)

	grid = Kit.frame({ Position = UDim2.fromOffset(16, 162), Size = UDim2.fromOffset(COLS * (CELL + GAP), ROWS * (CELL + GAP)), BackgroundTransparency = 1 }, root)
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromOffset(CELL, CELL)
	gl.CellPadding = UDim2.fromOffset(GAP, GAP)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	for i = 1, COLS * ROWS do
		local cell = makeCell(grid, function()
			if InventoryPanel.state and InventoryPanel.state.bag[i] then
				selected = { kind = "bag", index = i }
			else
				selected = nil
			end
			render()
		end)
		cell.LayoutOrder = i
		cells[i] = cell
	end

	runesLabel = Kit.text({ Position = UDim2.fromOffset(16, 162 + ROWS * (CELL + GAP) + 6), Size = UDim2.fromOffset(120, 22), Text = "", TextColor3 = UI.gold, TextXAlignment = Enum.TextXAlignment.Left }, root)
	countLabel = Kit.text({ Position = UDim2.fromOffset(140, 162 + ROWS * (CELL + GAP) + 6), Size = UDim2.fromOffset(90, 22), Text = "", TextColor3 = UI.muted, TextXAlignment = Enum.TextXAlignment.Left }, root)
	local sellCommon = Kit.button({ Position = UDim2.fromOffset(16, 162 + ROWS * (CELL + GAP) + 32), Size = UDim2.fromOffset(150, 28), Text = "Sell Commons", TextSize = 14, BackgroundColor3 = UI.panel }, root)
	Kit.stroke(sellCommon, UI.line, 1)
	sellCommon.Activated:Connect(function()
		send("sellcommon", 1)
	end)
	local sellUncommon = Kit.button({ Position = UDim2.fromOffset(174, 162 + ROWS * (CELL + GAP) + 32), Size = UDim2.fromOffset(190, 28), Text = "Sell Common+Uncommon", TextSize = 14, BackgroundColor3 = UI.panel }, root)
	Kit.stroke(sellUncommon, UI.line, 1)
	sellUncommon.Activated:Connect(function()
		send("sellcommon", 2)
	end)

	card = Kit.frame({
		Position = UDim2.new(1, -266, 0, 44),
		Size = UDim2.fromOffset(250, 410),
		BackgroundColor3 = Color3.fromRGB(20, 18, 16),
	}, root)
	Kit.stroke(card, UI.line, 1)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop = UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 8)
	pad.Parent = card
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 2)
	list.Parent = card

	Remotes.get("Inventory").OnClientEvent:Connect(function(state)
		InventoryPanel.state = state
		if selected and not selectedItem() then
			selected = nil
		end
		render()
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.I then
			InventoryPanel.toggle()
		end
	end)
	send("sync")
end

return InventoryPanel
