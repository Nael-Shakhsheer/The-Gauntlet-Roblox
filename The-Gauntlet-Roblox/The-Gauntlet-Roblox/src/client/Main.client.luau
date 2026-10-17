--!nonstrict
-- Client: hero select, HUD, dialogue box, damage numbers and attack input.
-- Interface styling follows the 2D game's woodland theme (parchment, timber, gold).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = require(Shared.Data)
local Palette = require(Shared.Palette)
local Remotes = require(Shared.Remotes)
local Sounds = require(Shared.Sounds)
local SkillsPanel = require(script.Parent.SkillsPanel)
local InventoryPanel = require(script.Parent.InventoryPanel)
local LootFx = require(script.Parent.LootFx)
local Minimap = require(script.Parent.Minimap)
local PartyFrames = require(script.Parent.PartyFrames)
local Life = require(script.Parent.Life)
local Feel = require(script.Parent.Feel)
local Controls = require(script.Parent.Controls)

local player = Players.LocalPlayer
local UI = Palette.UI

local gui = Instance.new("ScreenGui")
gui.Name = "GauntletHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- children always draw above their parent; ZIndex only orders siblings
gui.Parent = player:WaitForChild("PlayerGui")

-- Phones/small windows: shrink the whole HUD (it is built in fixed pixels for a 1280x720 screen).
local uiScale = Instance.new("UIScale")
uiScale.Parent = gui
local function rescaleHud()
	local camera = workspace.CurrentCamera
	if camera then
		local v = camera.ViewportSize
		uiScale.Scale = math.clamp(math.min(v.X / 1280, v.Y / 720), UserInputService.TouchEnabled and 0.75 or 0.6, 1)
	end
end
rescaleHud()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescaleHud)
end

local Kit = require(script.Parent.Kit)
local frame, text, button, outline = Kit.frame, Kit.text, Kit.button, Kit.stroke

-- ------------------------------------------------------------ area banner
local areaBanner = frame({
	Position = UDim2.new(0, 12, 0, 12),
	Size = UDim2.fromOffset(320, 38),
	BackgroundColor3 = UI.panel,
	BackgroundTransparency = 0.1,
}, gui)
outline(areaBanner)
local areaLabel = text({ Size = UDim2.fromScale(1, 1), Text = "…", TextColor3 = UI.gold, TextSize = 20 }, areaBanner)

-- ----------------------------------------------------------------- health
local hpBack = frame({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(320, 22),
	BackgroundColor3 = UI.bg,
}, gui)
outline(hpBack, UI.line)
local hpFill = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.red }, hpBack)
local hpText = text({ Size = UDim2.fromScale(1, 1), Text = "", TextSize = 15 }, hpBack)

local heroName = "Knight"
local function bindHumanoid(character)
	local humanoid = character:WaitForChild("Humanoid")
	local function update()
		hpFill.Size = UDim2.fromScale(math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1), 1)
		hpText.Text = ("%s  %d / %d"):format(heroName, math.ceil(humanoid.Health), humanoid.MaxHealth)
	end
	humanoid.HealthChanged:Connect(update)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)
	update()
end
player.CharacterAdded:Connect(bindHumanoid)
if player.Character then
	task.spawn(bindHumanoid, player.Character)
end

-- ---------------------------------------------------------------- dialogue
local dialogue = frame({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -150),
	Size = UDim2.fromOffset(560, 150),
	BackgroundColor3 = UI.paper,
	Visible = false,
}, gui)
outline(dialogue, UI.wood, 4)
local dialogueTitle = text({
	Position = UDim2.fromOffset(14, 8),
	Size = UDim2.new(1, -28, 0, 24),
	Text = "",
	TextColor3 = UI.paperInk,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 20,
}, dialogue)
local dialogueBody = text({
	Position = UDim2.fromOffset(14, 36),
	Size = UDim2.new(1, -28, 1, -76),
	Text = "",
	TextColor3 = UI.paperInk,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextSize = 17,
}, dialogue)
local nextButton = button({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -10),
	Size = UDim2.fromOffset(110, 28),
	BackgroundColor3 = UI.wood,
	Text = "Next",
}, dialogue)

local pages, pageIndex = {}, 1
local function showPage()
	dialogueBody.Text = pages[pageIndex] or ""
	nextButton.Text = pageIndex >= #pages and "Close" or "Next"
end
nextButton.Activated:Connect(function()
	if pageIndex >= #pages then
		dialogue.Visible = false
	else
		pageIndex += 1
		showPage()
	end
end)
Remotes.get("Dialogue").OnClientEvent:Connect(function(title, newPages)
	pages, pageIndex = newPages, 1
	dialogueTitle.Text = title
	dialogue.Visible = true
	showPage()
end)

-- ------------------------------------------------------------ notifications
local notice = text({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 64),
	Size = UDim2.fromOffset(520, 28),
	Text = "",
	TextColor3 = UI.red,
	TextStrokeTransparency = 0.4,
}, gui)
Remotes.get("Notify").OnClientEvent:Connect(function(message)
	notice.Text = message
	task.delay(3, function()
		if notice.Text == message then
			notice.Text = ""
		end
	end)
end)

-- Area banner + mood. The server tells each player which area they stand in; lighting is
-- per player so the party can be in different places of the connected world.
local Atmosphere = require(script.Parent.Atmosphere)
Atmosphere.init()
Remotes.get("AreaChanged").OnClientEvent:Connect(function(_, name, regionName)
	areaLabel.Text = name
	Atmosphere.apply(regionName)
end)

-- --------------------------------------------------------------- hero select
local heroSelect = frame({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(640, 400),
	BackgroundColor3 = UI.panel,
}, gui)
outline(heroSelect, UI.line, 3)
text({ Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 30), Text = "Choose your hero", TextColor3 = UI.gold, TextSize = 24 }, heroSelect)

local order = { "Knight", "Wizard", "Archer", "Cleric", "Rogue", "Druid", "Bard", "Healer" }
for i, hero in order do
	local info = Data.Heroes[hero]
	local col, row = (i - 1) % 4, (i - 1) // 4
	local card = button({
		Position = UDim2.fromOffset(16 + col * 154, 60 + row * 150),
		Size = UDim2.fromOffset(146, 140),
		BackgroundColor3 = UI.woodLight,
		Text = "",
	}, heroSelect)
	outline(card, Palette.hex(info.color), 2)
	frame({ Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = Palette.hex(info.color) }, card)
	text({ Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 24), Text = hero, TextColor3 = Palette.hex(info.color), TextSize = 20 }, card)
	text({
		Position = UDim2.fromOffset(6, 40),
		Size = UDim2.new(1, -12, 0, 40),
		Text = info.role,
		TextWrapped = true,
		TextSize = 14,
		TextColor3 = UI.muted,
	}, card)
	text({
		Position = UDim2.fromOffset(6, 88),
		Size = UDim2.new(1, -12, 0, 44),
		Text = ("HP %d   DMG %d\nSPD %d   RNG %d"):format(info.hp, info.damage, info.speed, info.range),
		TextSize = 13,
		TextColor3 = UI.ink,
	}, card)
	card.Activated:Connect(function()
		Remotes.get("SelectHero"):FireServer(hero)
		heroSelect.Visible = false
	end)
end

local heroButton = button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.fromOffset(110, 30),
	BackgroundColor3 = UI.panel,
	Text = "Hero",
}, gui)
outline(heroButton)
heroButton.Activated:Connect(function()
	if player:GetAttribute("HeroLocked") then
		return -- hero is bound once chosen (re-binding is a later mechanic)
	end
	heroSelect.Visible = not heroSelect.Visible
end)
local function syncHeroButton()
	heroButton.Visible = not player:GetAttribute("HeroLocked")
end
player:GetAttributeChangedSignal("HeroLocked"):Connect(syncHeroButton)
syncHeroButton()

SkillsPanel.init(gui)
SkillsPanel.onOpen = function()
	InventoryPanel.close()
end
InventoryPanel.onOpen = function()
	SkillsPanel.close()
end
local skillsButton = button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 48),
	Size = UDim2.fromOffset(110, 30),
	BackgroundColor3 = UI.panel,
	Text = "Skills (K)",
}, gui)
outline(skillsButton)
skillsButton.Activated:Connect(SkillsPanel.toggle)

for name, init in { InventoryPanel = function() InventoryPanel.init(gui) end, LootFx = LootFx.init, Minimap = function() Minimap.init(gui) end, PartyFrames = function() PartyFrames.init(gui) end, Life = function() task.spawn(Life.init) end } do
	local ok, err = xpcall(init, debug.traceback)
	if not ok then
		warn(("[Gauntlet] %s failed to start:\n%s"):format(name, tostring(err)))
	end
end
local bagButton = button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 84),
	Size = UDim2.fromOffset(110, 30),
	BackgroundColor3 = UI.panel,
	Text = "Bag (I)",
}, gui)
outline(bagButton)
bagButton.Activated:Connect(InventoryPanel.toggle)

Remotes.get("GuildOpen").OnClientEvent:Connect(function()
	heroSelect.Visible = true
end)
-- A saved hero was loaded (or already picked): skip the first-time selection screen.
task.spawn(function()
	for _ = 1, 40 do
		if player:GetAttribute("HeroLocked") then
			heroSelect.Visible = false
			return
		end
		task.wait(0.25)
	end
end)

Remotes.get("HeroChanged").OnClientEvent:Connect(function(hero)
	heroName = hero
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		hpText.Text = ("%s  %d / %d"):format(heroName, math.ceil(humanoid.Health), humanoid.MaxHealth)
	end
end)

-- -------------------------------------------------- level / runes / objective
local statPanel = frame({
	Position = UDim2.new(0, 12, 0, 56),
	Size = UDim2.fromOffset(320, 62),
	BackgroundColor3 = UI.panel,
	BackgroundTransparency = 0.1,
}, gui)
outline(statPanel)
local levelText = text({
	Position = UDim2.fromOffset(8, 4),
	Size = UDim2.new(1, -16, 0, 20),
	Text = "Lv 1   Runes 0",
	TextColor3 = UI.gold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 17,
}, statPanel)
local xpBack = frame({ Position = UDim2.fromOffset(8, 26), Size = UDim2.new(1, -16, 0, 8), BackgroundColor3 = UI.bg }, statPanel)
local xpFill = frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = UI.mint }, xpBack)
local gearText = text({
	Position = UDim2.fromOffset(8, 38),
	Size = UDim2.new(1, -16, 0, 20),
	Text = "",
	TextColor3 = UI.muted,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 13,
}, statPanel)

local function refreshStats()
	local level = player:GetAttribute("Level") or 1
	local xp, nextXp = player:GetAttribute("Xp") or 0, player:GetAttribute("XpNext") or 0
	levelText.Text = ("Lv %d   Runes %d"):format(level, player:GetAttribute("Runes") or 0)
	xpFill.Size = UDim2.fromScale(nextXp > 0 and math.clamp(xp / nextXp, 0, 1) or 1, 1)
	gearText.Text = ("%s  |  %s (-%d)"):format(
		player:GetAttribute("WeaponName") or "Bare hands",
		player:GetAttribute("ArmorName") or "No armour",
		player:GetAttribute("ArmorValue") or 0
	)
end
for _, attribute in { "Level", "Xp", "XpNext", "Runes", "WeaponName", "ArmorName", "ArmorValue" } do
	player:GetAttributeChangedSignal(attribute):Connect(refreshStats)
end
refreshStats()

local objectiveBox = frame({
	Position = UDim2.new(0, 12, 0, 124),
	Size = UDim2.fromOffset(320, 92),
	BackgroundColor3 = UI.panel,
	BackgroundTransparency = 0.25,
}, gui)
outline(objectiveBox, UI.line, 1)
local objectiveText = text({
	Position = UDim2.fromOffset(8, 4),
	Size = UDim2.new(1, -16, 1, -8),
	Text = "",
	TextColor3 = UI.ink,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextSize = 14,
}, objectiveBox)
local objectiveBase, bountyLine = "", ""
local function refreshObjective()
	objectiveText.Text = bountyLine ~= "" and (objectiveBase .. "\n" .. bountyLine) or objectiveBase
end
Remotes.get("Objective").OnClientEvent:Connect(function(message)
	objectiveBase = message
	refreshObjective()
end)
Remotes.get("Bounty").OnClientEvent:Connect(function(line)
	bountyLine = line or ""
	refreshObjective()
end)

-- ----------------------------------------------------- mana bar + hotbar
local manaBack = frame({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -42),
	Size = UDim2.fromOffset(320, 14),
	BackgroundColor3 = UI.bg,
}, gui)
outline(manaBack, UI.line, 1)
local manaFill = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(110, 150, 240) }, manaBack)
local manaText = text({ Size = UDim2.fromScale(1, 1), Text = "", TextSize = 12 }, manaBack)

local hotbar = frame({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -62),
	Size = UDim2.fromOffset(6 * 70, 66),
	BackgroundTransparency = 1,
}, gui)
local slotFrames = {}
local castEvent = Remotes.get("Cast")
local swingHook -- set in the combat-feel section below
local lastLightFx = 0
local function doCast(slot)
	if slotFrames[slot] and not slotFrames[slot].button.Visible then
		return -- ability not trained / equipped
	end
	Feel.faceNearest(40)
	castEvent:FireServer(slot)
	if slot <= 2 then
		if os.clock() - lastLightFx < 0.35 then
			return -- hold-to-repeat fires every 0.1 s; effects only as often as a Light can land
		end
		lastLightFx = os.clock()
	end
	Sounds.play(slot <= 2 and "light" or slot <= 4 and "special" or "ultimate")
	if swingHook then
		swingHook(slot)
	end
end
local TYPE_COLORS = { light = UI.line, special = UI.gold, ultimate = UI.red }
for slot = 1, 6 do
	local slotButton = button({
		Position = UDim2.fromOffset((slot - 1) * 70, 0),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = UI.panel,
		Text = "",
		AutoButtonColor = false,
	}, hotbar)
	local stroke = outline(slotButton, UI.line, 2)
	text({ Position = UDim2.fromOffset(3, 1), Size = UDim2.fromOffset(16, 14), Text = tostring(slot), TextSize = 12, TextColor3 = UI.muted }, slotButton)
	local nameLabel = text({
		Position = UDim2.fromOffset(2, 14),
		Size = UDim2.new(1, -4, 1, -28),
		Text = "",
		TextSize = 11,
		TextWrapped = true,
	}, slotButton)
	local costLabel = text({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -3, 1, -1),
		Size = UDim2.fromOffset(40, 12),
		Text = "",
		TextSize = 11,
		TextColor3 = Color3.fromRGB(140, 180, 255),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, slotButton)
	local cover = frame({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		ZIndex = 3,
	}, slotButton)
	local cdText = text({ Size = UDim2.fromScale(1, 1), Text = "", TextSize = 18, ZIndex = 4 }, slotButton)
	slotButton.MouseButton1Down:Connect(function()
		doCast(slot)
	end)
	slotFrames[slot] = { button = slotButton, stroke = stroke, name = nameLabel, cost = costLabel, cover = cover, cd = cdText, total = 1 }
end

local function setHotbar(hero)
	local set = Data.Abilities.sets[hero]
	for slot = 1, 6 do
		local ability, f = set[slot], slotFrames[slot]
		f.name.Text = ability.name
		f.cost.Text = ability.manaCost > 0 and tostring(ability.manaCost) or ""
		f.stroke.Color = TYPE_COLORS[ability.attackType] or UI.line
		f.total = math.max(ability.cooldown, 0.1)
	end
end
-- The hotbar shows only abilities the hero has trained (starters + skill-tree unlocks), centred.
local function applyLocks(state)
	if not state or state.hero ~= heroName then
		return
	end
	local set = Data.Abilities.sets[heroName]
	local shown = {}
	for slot = 1, 6 do
		local f, ability = slotFrames[slot], set[slot]
		local known = state.unlocked[ability.id] == true
		f.button.Visible = known
		f.cost.Text = ability.manaCost > 0 and tostring(ability.manaCost) or ""
		if known then
			table.insert(shown, slot)
		end
	end
	local offset = (6 - #shown) * 35
	for i, slot in shown do
		slotFrames[slot].button.Position = UDim2.fromOffset(offset + (i - 1) * 70, 0)
	end
end
SkillsPanel.onState = applyLocks
setHotbar(heroName)
applyLocks(SkillsPanel.state)
Remotes.get("HeroChanged").OnClientEvent:Connect(function(hero)
	setHotbar(hero)
	applyLocks(SkillsPanel.state)
end)

Remotes.get("Vitals").OnClientEvent:Connect(function(mana, maxMana, cooldowns, summoned)
	manaFill.Size = UDim2.fromScale(math.clamp(mana / math.max(maxMana, 1), 0, 1), 1)
	manaText.Text = ("Mana %d / %d"):format(math.floor(mana), maxMana)
	for slot = 1, 6 do
		local f = slotFrames[slot]
		local left = cooldowns[slot] or 0
		if summoned[slot] then
			f.cover.Size = UDim2.fromScale(1, 1)
			f.cd.Text = "alive"
			f.cd.TextSize = 12
		elseif left > 0.05 then
			f.cover.Size = UDim2.fromScale(1, math.clamp(left / f.total, 0, 1))
			f.cd.Text = left >= 1 and tostring(math.ceil(left)) or ("%.1f"):format(left)
			f.cd.TextSize = 18
		else
			f.cover.Size = UDim2.fromScale(1, 0)
			f.cd.Text = ""
		end
	end
end)

-- -------------------------------------------------------- floating rewards
Remotes.get("Reward").OnClientEvent:Connect(function(xp, runes, position)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = workspace
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromOffset(180, 26)
	board.AlwaysOnTop = true
	board.Adornee = anchor
	board.Parent = anchor
	local label = text({
		Size = UDim2.fromScale(1, 1),
		Text = ("+%d xp   +%d runes"):format(xp, runes),
		TextColor3 = UI.mint,
		TextStrokeTransparency = 0.3,
		TextSize = 17,
	}, board)
	TweenService:Create(anchor, TweenInfo.new(1.2), { Position = position + Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.3)
end)

-- ------------------------------------------------------------- shop panel
local shop = frame({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.fromOffset(640, 420),
	BackgroundColor3 = UI.paper,
	Visible = false,
	ZIndex = 10,
}, gui)
outline(shop, UI.wood, 4)
local shopTitle = text({
	Position = UDim2.fromOffset(14, 8),
	Size = UDim2.new(1, -120, 0, 26),
	Text = "Outfitter",
	TextColor3 = UI.paperInk,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 22,
	ZIndex = 11,
}, shop)
local shopRunes = text({
	Position = UDim2.fromOffset(14, 34),
	Size = UDim2.new(1, -28, 0, 20),
	Text = "",
	TextColor3 = UI.paperInk,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 15,
	ZIndex = 11,
}, shop)
local shopClose = button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 8),
	Size = UDim2.fromOffset(90, 28),
	BackgroundColor3 = UI.wood,
	Text = "Close",
	ZIndex = 11,
}, shop)
shopClose.Activated:Connect(function()
	shop.Visible = false
end)
local shopList = Instance.new("ScrollingFrame")
shopList.Position = UDim2.fromOffset(10, 62)
shopList.Size = UDim2.new(1, -20, 1, -72)
shopList.BackgroundTransparency = 1
shopList.BorderSizePixel = 0
shopList.ScrollBarThickness = 6
shopList.AutomaticCanvasSize = Enum.AutomaticSize.Y
shopList.CanvasSize = UDim2.new()
shopList.ZIndex = 11
shopList.Parent = shop
local shopLayout = Instance.new("UIListLayout")
shopLayout.Padding = UDim.new(0, 4)
shopLayout.Parent = shopList

local RARITY = {
	Common = Color3.fromRGB(230, 226, 205), Uncommon = Color3.fromRGB(150, 220, 120), Rare = Color3.fromRGB(130, 180, 255),
	Epic = Color3.fromRGB(210, 150, 255), Legendary = Color3.fromRGB(255, 190, 80),
}
Remotes.get("ShopOpen").OnClientEvent:Connect(function(stock, title)
	if title then
		shopTitle.Text = title
	end
	shop.Visible = true
	local level, runes = player:GetAttribute("Level") or 1, player:GetAttribute("Runes") or 0
	shopRunes.Text = ("Your runes: %d    Your level: %d"):format(runes, level)
	for _, child in shopList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, entry in stock do
		local row = frame({ Size = UDim2.new(1, -8, 0, 40), BackgroundColor3 = UI.wood, LayoutOrder = index, ZIndex = 12 }, shopList)
		local stat
		if entry.kind == "weapon" then
			stat = ("+%d damage"):format(entry.damage)
		elseif entry.kind == "consumable" then
			stat = ("%s  (owned %d)"):format(entry.description, entry.owned or 0)
		else
			stat = ("blocks %d damage per hit"):format(entry.armor)
		end
		text({
			Position = UDim2.fromOffset(8, 2),
			Size = UDim2.new(1, -230, 0, 20),
			Text = entry.name,
			TextColor3 = RARITY[entry.rarity] or UI.ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 16,
			ZIndex = 13,
		}, row)
		text({
			Position = UDim2.fromOffset(8, 21),
			Size = UDim2.new(1, -230, 0, 16),
			Text = ("%s  ·  %s  ·  needs Lv %d"):format(entry.rarity, stat, entry.level),
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = UI.muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 12,
			ZIndex = 13,
		}, row)
		local locked = level < entry.level
		local buy = button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(150, 28),
			BackgroundColor3 = locked and UI.panel or runes >= entry.price and Color3.fromRGB(70, 110, 50) or Color3.fromRGB(110, 60, 50),
			Text = locked and ("Lv %d needed"):format(entry.level) or ("Buy · %d runes"):format(entry.price),
			TextSize = 14,
			ZIndex = 13,
		}, row)
		buy.Activated:Connect(function()
			Remotes.get("Buy"):FireServer(entry.id)
		end)
	end
end)

-- ----------------------------------------------------------- travel panel
local travel = frame({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.fromOffset(420, 360),
	BackgroundColor3 = UI.paper,
	Visible = false,
	ZIndex = 10,
}, gui)
outline(travel, UI.wood, 4)
local travelTitle = text({
	Position = UDim2.fromOffset(14, 8),
	Size = UDim2.new(1, -120, 0, 26),
	Text = "Waystones",
	TextColor3 = UI.paperInk,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 22,
	ZIndex = 11,
}, travel)
button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 8),
	Size = UDim2.fromOffset(90, 28),
	BackgroundColor3 = UI.wood,
	Text = "Close",
	ZIndex = 11,
}, travel).Activated:Connect(function()
	travel.Visible = false
end)
local travelList = shopList:Clone()
travelList.Position = UDim2.fromOffset(10, 46)
travelList.Size = UDim2.new(1, -20, 1, -56)
for _, child in travelList:GetChildren() do
	if child:IsA("Frame") then
		child:Destroy()
	end
end
travelList.Parent = travel
Remotes.get("TravelOpen").OnClientEvent:Connect(function(list, title)
	travelTitle.Text = title or "Waystones"
	travel.Visible = true
	local level = player:GetAttribute("Level") or 1
	for _, child in travelList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for index, way in list do
		local usable = way.active and not way.here and level >= way.level
		local label = way.name
		if way.here then
			label ..= "  (you are here)"
		elseif not way.active then
			label ..= "  (not attuned)"
		elseif level < way.level then
			label ..= ("  (needs Lv %d)"):format(way.level)
		end
		local b = button({
			Size = UDim2.new(1, -8, 0, 34),
			BackgroundColor3 = usable and UI.wood or UI.panel,
			Text = label,
			TextColor3 = usable and UI.ink or UI.muted,
			TextSize = 15,
			LayoutOrder = index,
			ZIndex = 12,
		}, travelList)
		b.Activated:Connect(function()
			if usable then
				Remotes.get("Travel"):FireServer(way.id)
				travel.Visible = false
			end
		end)
	end
end)

-- ------------------------------------------------------------ level gates
-- Server-built barrier parts (tag LevelGate) only exist for players below the level:
-- collision and visibility are switched on locally (the server value stays non-colliding).
local function applyGate(part)
	local locked = (player:GetAttribute("Level") or 1) < (part:GetAttribute("ReqLevel") or 1)
	if part:GetAttribute("Label") then
		local gui = part:FindFirstChildWhichIsA("BillboardGui")
		if gui then
			gui.Enabled = locked
		end
	else
		part.CanCollide = locked
		part.Transparency = locked and 0.6 or 1
	end
end
CollectionService:GetInstanceAddedSignal("LevelGate"):Connect(applyGate)
for _, part in CollectionService:GetTagged("LevelGate") do
	applyGate(part)
end
player:GetAttributeChangedSignal("Level"):Connect(function()
	for _, part in CollectionService:GetTagged("LevelGate") do
		applyGate(part)
	end
end)

-- ------------------------------------------------------------- pouch (potions)
local POUCH_KEYS = { Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C, Enum.KeyCode.V, Enum.KeyCode.B, Enum.KeyCode.N, Enum.KeyCode.M }
local POUCH_NAMES = { "Z", "X", "C", "V", "B", "N", "M" }
local pouchBar = frame({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -12),
	Size = UDim2.fromOffset(7 * 58, 54),
	BackgroundTransparency = 1,
}, gui)
local pouchLayout = Instance.new("UIListLayout")
pouchLayout.FillDirection = Enum.FillDirection.Horizontal
pouchLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
pouchLayout.Padding = UDim.new(0, 4)
pouchLayout.Parent = pouchBar
local pouchIds = {}
local POTION_COLORS = {
	healing_draught = "#ee847d", mana_draught = "#759fbf", warding_tonic = "#d2b36f", quickstep_elixir = "#9fd3e6",
	ember_oil = "#e08a3c", phoenix_flask = "#ff6b4a", stormguard_charm = "#b59bcd",
}
local function usePotion(index)
	local id = pouchIds[index]
	if id then
		Remotes.get("UseItem"):FireServer(id)
	end
end
local function refreshPouch()
	for _, child in pouchBar:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	pouchIds = {}
	local raw = player:GetAttribute("Pouch") or ""
	for entry in string.gmatch(raw, "[^,]+") do
		local id, count = string.match(entry, "^(.-):(%d+)$")
		if id and Data.Items.items[id] then
			table.insert(pouchIds, id)
			local index = #pouchIds
			local slot = button({
				Size = UDim2.fromOffset(54, 54),
				BackgroundColor3 = UI.panel,
				Text = "",
				AutoButtonColor = true,
				LayoutOrder = index,
			}, pouchBar)
			outline(slot, Palette.hex(POTION_COLORS[id] or "#c1c3aa"), 2)
			frame({ Position = UDim2.fromOffset(17, 8), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = Palette.hex(POTION_COLORS[id] or "#c1c3aa") }, slot)
			text({ Position = UDim2.fromOffset(2, 0), Size = UDim2.fromOffset(14, 12), Text = POUCH_NAMES[index] or "", TextSize = 11, TextColor3 = UI.muted }, slot)
			text({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -3, 1, -1), Size = UDim2.fromOffset(30, 12), Text = "x" .. count, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right }, slot)
			text({ Position = UDim2.fromOffset(2, 30), Size = UDim2.new(1, -4, 0, 22), Text = Data.Items.items[id].name, TextSize = 9, TextWrapped = true, TextColor3 = UI.ink }, slot)
			slot.Activated:Connect(function()
				usePotion(index)
			end)
		end
	end
end
player:GetAttributeChangedSignal("Pouch"):Connect(refreshPouch)
refreshPouch()

-- ----------------------------------------------------------- objective compass
local compass = frame({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(190, 50),
	BackgroundColor3 = UI.panel,
	BackgroundTransparency = 0.25,
	Visible = false,
}, gui)
outline(compass, UI.line, 1)
local compassArrow = text({ Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(40, 46), Text = "▲", TextSize = 34, TextColor3 = UI.gold }, compass)
local compassLabel = text({ Position = UDim2.fromOffset(46, 4), Size = UDim2.new(1, -50, 0, 22), Text = "", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, compass)
local compassDist = text({ Position = UDim2.fromOffset(46, 26), Size = UDim2.new(1, -50, 0, 18), Text = "", TextSize = 14, TextColor3 = UI.gold, TextXAlignment = Enum.TextXAlignment.Left }, compass)
local waypoint, waypointName = nil, ""
Remotes.get("Waypoint").OnClientEvent:Connect(function(position, label)
	waypoint, waypointName = position, label or ""
	compass.Visible = waypoint ~= nil
end)
game:GetService("RunService").RenderStepped:Connect(function()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not (waypoint and root and camera) then
		return
	end
	local delta = Vector3.new(waypoint.X - root.Position.X, 0, waypoint.Z - root.Position.Z)
	compassDist.Text = ("%d studs"):format(math.floor(delta.Magnitude))
	compassLabel.Text = waypointName
	local look = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	if delta.Magnitude > 0.1 and look.Magnitude > 0.01 then
		local angle = math.deg(math.atan2(delta.X, delta.Z) - math.atan2(look.X, look.Z))
		compassArrow.Rotation = -angle
	end
end)

-- ------------------------------------------------------------ combat feel
local RunService = game:GetService("RunService")
local shake = 0
local function addShake(amount)
	shake = math.min(1, shake + amount)
end
RunService.RenderStepped:Connect(function(dt)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if shake > 0.01 then
		humanoid.CameraOffset = Vector3.new((math.random() - 0.5) * shake * 1.4, (math.random() - 0.5) * shake, 0)
		shake = math.max(0, shake - dt * 2.5)
	elseif humanoid.CameraOffset ~= Vector3.zero then
		humanoid.CameraOffset = Vector3.zero
	end
end)

local function watchHealth(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	local last = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < last - 0.5 and health > 0 then
			addShake(math.clamp((last - health) / math.max(humanoid.MaxHealth, 1) * 5, 0.2, 0.9))
			Sounds.play("hurt")
		end
		last = health
	end)
end
player.CharacterAdded:Connect(watchHealth)
if player.Character then
	task.spawn(watchHealth, player.Character)
end

Remotes.get("Reward").OnClientEvent:Connect(function()
	Sounds.play("loot")
end)
Remotes.get("Notify").OnClientEvent:Connect(function(message)
	if type(message) == "string" then
		if message:find("^Level up") then
			Sounds.play("levelup")
			addShake(0.15)
		elseif message:find("^Bought") or message:find("^Found") then
			Sounds.play("potion")
		end
	end
end)

-- Ability visuals (props, poses, world effects) live in AbilityFx; the server broadcasts each cast.
local AbilityFx = require(script.Parent.AbilityFx)
AbilityFx.shake = addShake
Remotes.get("AbilityFx").OnClientEvent:Connect(AbilityFx.play)
swingHook = function(slot)
	if slot > 4 then
		addShake(0.1)
	end
end

-- ------------------------------------------------------------- controls help
local helpPanel = frame({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(500, 350),
	BackgroundColor3 = UI.panel,
	ZIndex = 20,
}, gui)
outline(helpPanel, UI.gold, 3)
text({ Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 28), Text = "The Gauntlet · Adventure", TextColor3 = UI.gold, TextSize = 22, ZIndex = 21 }, helpPanel)
text({
	Position = UDim2.fromOffset(18, 46),
	Size = UDim2.new(1, -36, 1, -90),
	Text = table.concat(
		Controls.isTouch() and {
			"Left thumb      move       Right thumb  camera",
			"Big button      attack (hold to repeat)",
			"Round buttons   abilities (Special / Ultimate)",
			"Dodge           roll with brief invulnerability",
			"Run             toggle sprint (not in combat)",
			"Tap prompts     talk, open, rest, use",
			"Potions         tap the pouch bar (left)",
			"Skills (top right)  skill tree - train in Oakvale / Dunmere",
			"",
			"Hit enemies to build a COMBO: more damage and faster Ultimates.",
			"A well-timed dodge through an attack is a PERFECT DODGE:",
			"free mana and Ultimate charge. Levels unlock harder areas.",
			"Follow the gold arrow for your current quest.",
		} or {
			"WASD / Space    move, jump          Shift  sprint",
			"Left / Right click   Light attacks (hold to repeat)",
			"1-6             abilities (Light, Special, Ultimate)",
			"Q               dodge roll (brief invulnerability)",
			"E               interact (NPCs, shops, beds, stones)",
			"Z X C V B N M   use potions from your pouch",
			"K               skill tree (train in Oakvale / Dunmere)",
			"I               inventory & gear (walk over drops to loot)",
			"H               show / hide this help",
			Controls.hasGamepad() and "Gamepad: RT/LT lights, X Y R1 L1 abilities, B dodge, D-pad potions" or "",
			"",
			"Hit enemies to build a COMBO: more damage and faster Ultimates.",
			"Dodge through an attack for a PERFECT DODGE (mana + Ultimate).",
			"Follow the gold arrow for your current quest.",
		},
		"\n"
	),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextSize = 14,
	ZIndex = 21,
}, helpPanel)
local helpClose = button({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.fromOffset(120, 30),
	BackgroundColor3 = UI.wood,
	Text = "Got it",
	ZIndex = 21,
}, helpPanel)
helpClose.Activated:Connect(function()
	helpPanel.Visible = false
end)
helpPanel.Visible = false
task.delay(3, function()
	-- Show once the hero screen is out of the way.
	helpPanel.Visible = not heroSelect.Visible
end)

-- ------------------------------------------------------------------- input
local KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
}
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		doCast(1)
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		doCast(2)
	elseif KEYS[input.KeyCode] then
		doCast(KEYS[input.KeyCode])
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		Remotes.get("Sprint"):FireServer(true)
	elseif input.KeyCode == Enum.KeyCode.H then
		helpPanel.Visible = not helpPanel.Visible
	else
		local index = table.find(POUCH_KEYS, input.KeyCode)
		if index then
			usePotion(index)
		end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		Remotes.get("Sprint"):FireServer(false)
	end
end)

-- --------------------------------------------------- feel + platform controls
Feel.shake = addShake
Feel.init(gui)
local slotButtons = {}
for slot = 1, 6 do
	slotButtons[slot] = slotFrames[slot].button
end
Controls.init(gui, {
	doCast = doCast,
	usePotion = usePotion,
	slotButtons = slotButtons,
	hotbar = hotbar,
	pouchBar = pouchBar,
	toggleSkills = SkillsPanel.toggle,
	toggleBag = InventoryPanel.toggle,
	blocked = function()
		return shop.Visible or travel.Visible or heroSelect.Visible or dialogue.Visible or helpPanel.Visible or SkillsPanel.visible() == true or InventoryPanel.visible() == true
	end,
})
