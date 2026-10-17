--!nonstrict
-- Per-player combat state shared by combat, enemy AI and regeneration:
-- mana, ward (damage taken factor), damage boost, speed boost, taunt, invisibility.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local Progress = require(script.Parent.Progress)
local State = require(script.Parent.State)

local Stats = {}

local all = {}

local function fresh()
	return {
		mana = 100,
		maxMana = 100,
		wardUntil = 0,
		wardFactor = 1,
		boostUntil = 0,
		boost = 1,
		speedUntil = 0,
		speedFactor = 1,
		tauntUntil = 0,
		invisibleUntil = 0,
		lastCombat = 0,
		iframeUntil = 0,
		dodgeReadyAt = 0,
		lastPerfect = 0,
		lastHitAt = 0,
		combo = 0,
		comboUntil = 0,
	}
end

function Stats.get(player: Player)
	local s = all[player]
	if not s then
		s = fresh()
		all[player] = s
	end
	return s
end

function Stats.reset(player: Player)
	all[player] = fresh()
	return all[player]
end

function Stats.drop(player: Player)
	all[player] = nil
end

-- Damage multiplier from boosts (Spell Surge, Battle Anthem...).
function Stats.damageFactor(player: Player, now: number): number
	local s = Stats.get(player)
	return s.boostUntil > now and s.boost or 1
end

-- Combo: consecutive hits within COMBO_WINDOW raise damage a little and shave Ultimate cooldowns.
function Stats.comboFactor(player: Player, now: number): number
	local s = Stats.get(player)
	if s.comboUntil <= now then
		return 1
	end
	return 1 + math.min(s.combo, Config.COMBO_MAX) * Config.COMBO_STEP
end

-- Called for every direct (non damage-over-time) hit a player lands. Returns the new combo count.
function Stats.registerHit(player: Player, now: number, crit: boolean): number
	local s = Stats.get(player)
	if s.comboUntil <= now then
		s.combo = 0
	end
	s.comboUntil = now + Config.COMBO_WINDOW
	s.lastCombat = now
	if now - s.lastHitAt < 0.12 then
		return s.combo -- one swing hitting many foes counts once (no combo/charge farming with AoE)
	end
	s.lastHitAt = now
	s.combo += 1
	local cooldowns = State.cooldowns[player]
	if cooldowns then
		local shave = Config.ULT_SHAVE_HIT * (crit and 2 or 1) * (1 + Progress.bonus(player).ult)
		for _, slot in { 5, 6 } do
			if (cooldowns[slot] or 0) > now then
				cooldowns[slot] = math.max(now, cooldowns[slot] - shave)
			end
		end
	end
	return s.combo
end

-- A hit that would have landed during dodge i-frames: reward the read.
local function perfectDodge(player: Player, s, now: number)
	if now - s.lastPerfect < 0.6 then
		return
	end
	s.lastPerfect = now
	s.mana = math.min(s.maxMana, s.mana + 8)
	local cooldowns = State.cooldowns[player]
	if cooldowns then
		for _, slot in { 5, 6 } do
			if (cooldowns[slot] or 0) > now then
				cooldowns[slot] = math.max(now, cooldowns[slot] - 1.5)
			end
		end
	end
	Remotes.get("Notify"):FireClient(player, "Perfect dodge!")
end

-- Enemy damage on a player: i-frames first, then armour, then an active ward (factor = share still taken).
function Stats.hurt(player: Player, humanoid: Humanoid, amount: number, now: number)
	local s = Stats.get(player)
	if s.iframeUntil > now then
		perfectDodge(player, s, now)
		return
	end
	-- armour blocks flat damage per hit, but never more than 75% of it
	amount = math.max(math.ceil(amount * 0.25), amount - Progress.armorValue(player))
	if s.wardUntil > now then
		amount = math.max(1, math.round(amount * s.wardFactor))
	end
	s.lastCombat = now
	humanoid:TakeDamage(amount)
end

return Stats
