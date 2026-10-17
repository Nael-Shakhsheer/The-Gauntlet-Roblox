--!nonstrict
-- Dunmere chapter chain (chapter_flow.py / region_content.py), after the woodland is secured:
--   failed_harvest: inspect dry_ditch, rooted_crop, empty_granary -> report to the Dunmere runner
--   irrigation:     clear the mill approach, clear both channels, operate the sluice -> report
--   mill_cellar:    clear cellar approach, open the pump chamber (sealed Overseer fight), read ledger -> report
--   outcome:        inspect the restored field -> report (chapter ends)
-- Stages live in State.quests (new | active | done); evidence in State.claimed["ev:<key>"] (both persist).
-- Simplification vs 2D: finishing a report auto-accepts the next assignment.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = require(Shared.Data)
local Coord = require(Shared.Coord)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.State)
local Progress = require(script.Parent.Progress)
local EnemyService = require(script.Parent.EnemyService)
local DungeonService = require(script.Parent.DungeonService)

local RC = Data.RegionContent

local Dunmere = {}
Dunmere.onChange = nil -- set by Quests: refresh objective/waypoint

local STAGES = {
	{
		key = "failed_harvest",
		title = "The Harvest That Never Came",
		need = { "dry_ditch", "rooted_crop", "empty_granary" },
		ask = "Inspect the dry ditch, the rooted crop and the empty granary in the failed fields, then report back.",
		report = "The three sites show roots and an unusual additive, not drought alone. Clear the mill's two channels and reopen the sluice.",
		xp = 150, runes = 40,
	},
	{
		key = "irrigation",
		title = "Water for the Living",
		need = { "channel_west", "channel_east", "sluice_open" },
		ask = "Clear the mill approach, remove both channel blockages and operate the sluice.",
		report = "One irrigation strip runs again and green shoots survive. The mill cellar holds the missing delivery records.",
		xp = 220, runes = 60,
	},
	{
		key = "mill_cellar",
		title = "Under the Mill",
		need = { "overseer_defeated", "additive_ledger" },
		ask = "Enter the mill cellar, defeat the Blighted Overseer and recover its additive ledger.",
		report = "The ledger shows the steward concealed the additive's risks. Inspect the restored field before the final report.",
		xp = 320, runes = 90,
	},
	{
		key = "outcome",
		title = "A Harvest Worth Saving",
		need = { "field_restored" },
		ask = "Inspect the restored field and deliver the ledger to the village runner.",
		report = "Dunmere's mill crisis is resolved. Water reaches a living strip and the harmful additive is withdrawn. The pumping works and Ashen Ridge remain later leads.",
		xp = 400, runes = 120,
	},
}

local FEATURE_TEXT = {
	dry_ditch = "The irrigation ditch is dry above a knot of roots. Drought alone does not explain the blockage.",
	rooted_crop = "Harvest additive coats the failed crop. Small roots spread where the mixture settled.",
	empty_granary = "The grain bins are empty. A delivery note mentions a concentrated additive from the mill cellar.",
	field_restored = "Water reaches one repaired strip. Green shoots survive along the ditch; the rest of Dunmere still needs help. Bring word to the runner.",
	additive_ledger = "The steward concealed the risks of material raised from the pumping tunnels. The additive first improved yields, then fed the roots.",
}

local function tell(player: Player, text: string)
	Remotes.get("Notify"):FireClient(player, text)
end

local function party(fn)
	for _, p in Players:GetPlayers() do
		fn(p)
	end
end

local function have(ev: string): boolean
	return State.claimed["ev:" .. ev] == true
end

local function changed()
	if Dunmere.onChange then
		Dunmere.onChange()
	end
end

-- Current assignment (first not done) or nil when the chapter is finished.
local function current()
	for _, s in STAGES do
		if State.quests[s.key] ~= "done" then
			return s
		end
	end
	return nil
end

local function allFound(s): boolean
	for _, ev in s.need do
		if not have(ev) then
			return false
		end
	end
	return true
end

local function unlocked(): boolean
	return State.quests.region == "done"
end

local function say(player: Player, title: string, text: string)
	Remotes.get("Dialogue"):FireClient(player, title, { text })
end

local function cleared(area: string, ...: string): boolean
	for _, g in { ... } do
		if not EnemyService.groupCleared(area, g) then
			return false
		end
	end
	return true
end

local function evidence(player: Player, key: string, extra: string?)
	if not have(key) then
		State.claimed["ev:" .. key] = true
		party(function(p)
			tell(p, "Evidence found: " .. key:gsub("_", " "))
		end)
		changed()
	end
	say(player, key:gsub("_", " "), (FEATURE_TEXT[key] or RC.TEXT[key] or "") .. (extra and (" " .. extra) or ""))
end

local function runner(player: Player)
	if not unlocked() then
		say(player, "Dunmere runner", "Oakvale's runner has not sent word yet. Finish securing the woodland first.")
		return
	end
	local s = current()
	if not s then
		say(player, "Dunmere runner", "The mill runs and the field is green. Dunmere will remember you. Ashen Ridge and the pumping works are still ahead.")
		return
	end
	local st = State.quests[s.key]
	if st == "new" then
		State.quests[s.key] = "active"
		say(player, s.title, s.ask)
		changed()
	elseif allFound(s) then
		State.quests[s.key] = "done"
		party(function(p)
			Progress.addXp(p, s.xp)
			Progress.addRunes(p, s.runes)
			tell(p, ("%s complete  +%d xp  +%d runes"):format(s.title, s.xp, s.runes))
		end)
		local nxt = current()
		if nxt then
			State.quests[nxt.key] = "active"
		end
		say(player, s.title, s.report .. (nxt and ("\n\nNext: " .. nxt.title .. " - " .. nxt.ask) or ""))
		changed()
	else
		say(player, s.title, s.ask)
	end
end

local CLUES = { dry_ditch = "failed_harvest", rooted_crop = "failed_harvest", empty_granary = "failed_harvest", field_restored = "outcome" }

function Dunmere.interact(player: Player, feature): boolean
	local key, area = feature.key, feature.area
	if key == "runner" and area == "dunmere" then
		runner(player)
		return true
	end
	local s = current()
	local function needStage(stage: string): boolean
		if not unlocked() or not s or s.key ~= stage or State.quests[stage] ~= "active" then
			tell(player, "Speak to the Dunmere runner for your assignment first.")
			return false
		end
		return true
	end
	if CLUES[key] then
		if CLUES[key] == "outcome" and (not s or s.key ~= "outcome" or State.quests.outcome ~= "active") then
			tell(player, "The field is only worth inspecting once the cellar is cleared and the runner sends you.")
			return true
		end
		if needStage(CLUES[key]) then
			evidence(player, key)
		end
		return true
	elseif key == "channel_west" or key == "channel_east" then
		if not needStage("irrigation") then
			return true
		end
		if not cleared("mill", "mill-approach", "mill-approach-flank") then
			tell(player, "Clear the mill approach guards first.")
			return true
		end
		evidence(player, key, "The channel runs free.")
		return true
	elseif key == "sluice_open" then
		if not needStage("irrigation") then
			return true
		end
		if not (have("channel_west") and have("channel_east")) then
			tell(player, "Both channels must be cleared before the sluice will turn.")
			return true
		end
		evidence(player, key, "Water pours into the ditch.")
		return true
	elseif key == "cellar_begin" then
		if not needStage("mill_cellar") then
			return true
		end
		if not cleared("cellar", "cellar-approach") then
			tell(player, "Clear the cellar approach before opening the pump chamber.")
			return true
		end
		DungeonService.begin(player, feature)
		return true
	elseif key == "additive_ledger" then
		if not have("overseer_defeated") then
			tell(player, "The ledger is locked in the pump chamber. Defeat the Overseer first.")
			return true
		end
		if needStage("mill_cellar") then
			evidence(player, key)
		end
		return true
	end
	return false
end

-- Objective HUD text for the Dunmere phase (after the woodland).
function Dunmere.objective(): string?
	if not unlocked() then
		return nil
	end
	local s = current()
	if not s then
		return "Dunmere's crisis is resolved. Level up and gear up - Ashen Ridge awaits."
	end
	local line
	if State.quests[s.key] == "new" then
		line = "Speak to the Village Runner in Dunmere (south down the border road)."
	elseif allFound(s) then
		line = "Report to the Dunmere runner."
	else
		line = s.title .. ": " .. s.ask
	end
	local marks = {}
	for _, st in STAGES do
		table.insert(marks, (State.quests[st.key] == "done" and "[x] " or "[ ] ") .. st.title)
	end
	return line .. "\n" .. table.concat(marks, "  ")
end

-- feature key, label, area id of the next step.
function Dunmere.target(): (string?, string?, string?)
	if not unlocked() then
		return nil
	end
	local s = current()
	if not s then
		return nil
	end
	if State.quests[s.key] == "new" or allFound(s) then
		return "runner", "Dunmere runner", "dunmere"
	end
	for _, ev in s.need do
		if not have(ev) then
			if ev == "overseer_defeated" then
				return "cellar_begin", "Pump chamber seal", "cellar"
			end
			for area, list in RC.FEATURES do
				for _, f in list do
					if f[1] == ev then
						return ev, f[2], area
					end
				end
			end
		end
	end
	return nil
end

-- World position of a feature in an area (nil if unknown).
function Dunmere.position(key: string, area: string): Vector3?
	local info = State.areas[area]
	if not info then
		return nil
	end
	local list = RC.FEATURES[area] or {}
	for _, f in list do
		if f[1] == key then
			local gx, gy = Coord.scaleToArea(f[3], f[4], info.widthPx, info.heightPx)
			return Coord.toWorld(info.origin, gx, gy, 0)
		end
	end
	return nil
end

function Dunmere.start()
	DungeonService.completed = function(dungeon)
		if dungeon == "cellar" then
			State.claimed["ev:overseer_defeated"] = true
			changed()
		end
	end
end

return Dunmere
