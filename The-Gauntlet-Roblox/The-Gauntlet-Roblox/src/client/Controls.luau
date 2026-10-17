--!nonstrict
-- Input layer for keyboard/mouse, touch and gamepad.
--  * Dodge button (Q / B / on-screen) with cooldown cover.
--  * Touch: ability buttons re-laid in an arc around a big attack button, sprint toggle,
--    pouch moved out of the thumbstick area, bigger HUD scale.
--  * Gamepad: triggers/bumpers/face buttons for abilities, D-pad for potions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Kit = require(script.Parent.Kit)
local Feel = require(script.Parent.Feel)

local Controls = {}
local UI = Kit.UI

local held = {} -- [slot] = true while a hold-to-repeat input is down
local dodgeCover
local sprintOn = false
local sprintButton

function Controls.isTouch(): boolean
	return UserInputService.TouchEnabled
end

function Controls.hasGamepad(): boolean
	return UserInputService.GamepadEnabled
end

local function setSprint(on: boolean)
	sprintOn = on
	Remotes.get("Sprint"):FireServer(on)
	if sprintButton then
		sprintButton.BackgroundColor3 = on and Color3.fromRGB(70, 110, 60) or UI.panel
	end
end

local function roundButton(props, parent): TextButton
	local b = Kit.button(props, parent)
	b.AutoButtonColor = false
	Kit.stroke(b, UI.gold, 2)
	return b
end

-- ctx = { doCast, usePotion, slotButtons = {[1..6] = TextButton}, hotbar, pouchBar, toggleSkills }
function Controls.init(gui: ScreenGui, ctx)
	local touch = Controls.isTouch()

	-- Dodge button (all platforms).
	local size = touch and 66 or 58
	local dodgeButton = roundButton({
		AnchorPoint = Vector2.new(1, 1),
		Position = touch and UDim2.new(1, -200, 1, -30) or UDim2.new(0.5, -230, 1, -62),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = UI.panel,
		Text = touch and "Dodge" or "",
		TextSize = 13,
	}, gui)
	dodgeButton.Name = "DodgeButton"
	if not touch then
		Kit.text({ Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(16, 14), Text = "Q", TextSize = 12, TextColor3 = UI.muted }, dodgeButton)
		Kit.text({ Size = UDim2.fromScale(1, 1), Text = "Dodge", TextSize = 12 }, dodgeButton)
	end
	dodgeCover = Kit.frame({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		ZIndex = 3,
	}, dodgeButton)
	dodgeButton.MouseButton1Down:Connect(function()
		Feel.dodge()
	end)

	if touch then
		-- Arc of ability buttons around the attack button, bottom-right.
		local spots = {
			[1] = { 92, 24, 24 }, -- size, right inset, bottom inset (attack)
			[2] = { 64, 126, 30 },
			[3] = { 64, 118, 126 },
			[4] = { 64, 46, 126 },
			[5] = { 64, 46, 206 },
			[6] = { 64, 118, 206 },
		}
		for slot, spec in spots do
			local b = ctx.slotButtons[slot]
			if b then
				b.Parent = gui
				b.AnchorPoint = Vector2.new(1, 1)
				b.Size = UDim2.fromOffset(spec[1], spec[1])
				b.Position = UDim2.new(1, -spec[2], 1, -spec[3])
			end
		end
		ctx.hotbar.Visible = false
		-- Pouch out of the thumbstick corner.
		ctx.pouchBar.AnchorPoint = Vector2.new(0, 1)
		ctx.pouchBar.Position = UDim2.new(0, 12, 1, -190)
		local layout = ctx.pouchBar:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		end
		sprintButton = roundButton({
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -200, 1, -106),
			Size = UDim2.fromOffset(58, 58),
			BackgroundColor3 = UI.panel,
			Text = "Run",
			TextSize = 14,
		}, gui)
		sprintButton.MouseButton1Down:Connect(function()
			setSprint(not sprintOn)
		end)
	end

	-- Hold-to-repeat for the two Lights: mouse buttons, on-screen buttons, gamepad triggers.
	for _, slot in { 1, 2 } do
		local b = ctx.slotButtons[slot]
		if b then
			b.MouseButton1Down:Connect(function()
				held[slot] = true
			end)
			b.MouseButton1Up:Connect(function()
				held[slot] = nil
			end)
			b.MouseLeave:Connect(function()
				held[slot] = nil
			end)
		end
	end

	local GAMEPAD_SLOTS = {
		[Enum.KeyCode.ButtonR2] = 1, [Enum.KeyCode.ButtonL2] = 2, [Enum.KeyCode.ButtonX] = 3,
		[Enum.KeyCode.ButtonY] = 4, [Enum.KeyCode.ButtonR1] = 5, [Enum.KeyCode.ButtonL1] = 6,
	}
	local DPAD_POTIONS = { [Enum.KeyCode.DPadUp] = 1, [Enum.KeyCode.DPadRight] = 2, [Enum.KeyCode.DPadDown] = 3, [Enum.KeyCode.DPadLeft] = 4 }
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Q or key == Enum.KeyCode.ButtonB then
			Feel.dodge()
		elseif GAMEPAD_SLOTS[key] then
			ctx.doCast(GAMEPAD_SLOTS[key])
		elseif DPAD_POTIONS[key] then
			ctx.usePotion(DPAD_POTIONS[key])
		elseif key == Enum.KeyCode.ButtonL3 then
			setSprint(not sprintOn)
		elseif key == Enum.KeyCode.ButtonSelect then
			ctx.toggleSkills()
		elseif key == Enum.KeyCode.ButtonStart and ctx.toggleBag then
			ctx.toggleBag()
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		-- dodge cooldown cover
		dodgeCover.Size = UDim2.fromScale(1, 1 - Feel.dodgeReadiness())
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		if ctx.blocked and ctx.blocked() then
			return
		end
		if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) or held[1] or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR2) then
			ctx.doCast(1)
		elseif UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) or held[2] or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL2) then
			ctx.doCast(2)
		end
	end)
end

return Controls
