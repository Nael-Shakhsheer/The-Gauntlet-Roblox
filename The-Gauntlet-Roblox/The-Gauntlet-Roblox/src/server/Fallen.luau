--!nonstrict
-- Death handling for co-op: a downed hero stays "fallen" for a while so an ally can
-- revive them (Quick Revival, Mass Revival, Cleansing Splash); otherwise they return
-- at the world start. If the whole party falls everyone returns after a short beat.
-- TODO(port): wipes and recovery rules from adventure_recovery.py.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.State)
local Persistence = require(script.Parent.Persistence)

local Fallen = {}

local FALLEN_SECONDS = 15
local SOLO_FALLEN_SECONDS = 4
local WIPE_SECONDS = 5

function Fallen.respawn(player: Player)
	State.fallen[player] = nil
	if player.Parent then
		player:LoadCharacter()
	end
end

-- Brings a fallen player back where `pos` is, at a share of their health.
function Fallen.revive(player: Player, pos: Vector3, fraction: number): boolean
	if not State.fallen[player] then
		return false
	end
	State.reviveAt[player] = { pos = pos, fraction = fraction }
	State.fallen[player] = nil
	player:LoadCharacter()
	return true
end

local function checkWipe()
	for _, player in Players:GetPlayers() do
		if not State.fallen[player] then
			return
		end
	end
	task.delay(WIPE_SECONDS, function()
		for _, player in Players:GetPlayers() do
			if State.fallen[player] then
				Fallen.respawn(player)
			end
		end
	end)
end

local function hook(player: Player)
	player.CharacterAdded:Connect(function(character)
		State.fallen[player] = nil
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			local root = character:FindFirstChild("HumanoidRootPart")
			local record = { pos = root and root.Position or State.spawn, at = os.clock() }
			State.fallen[player] = record
			-- Alone there is nobody to revive you, so the wait is short; in a party allies get a window.
			local wait = #Players:GetPlayers() > 1 and FALLEN_SECONDS or SOLO_FALLEN_SECONDS
			Remotes.get("Notify"):FireClient(player, wait == FALLEN_SECONDS and ("You have fallen. An ally can revive you, or you return in %d seconds."):format(wait) or "You have fallen. Returning to your last bed or waystone...")
			task.delay(wait, function()
				if State.fallen[player] == record then
					Fallen.respawn(player)
				end
			end)
			checkWipe()
		end)
	end)
	task.spawn(function()
		Persistence.waitLoaded(player)
		if not player.Parent then
			return
		end
		player:LoadCharacter() -- (re)load so every spawn goes through the hero/spawn hooks
	end)
end

-- Call after HeroService.start so its CharacterAdded handlers exist before the first spawn.
function Fallen.start()
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		State.fallen[player] = nil
		State.reviveAt[player] = nil
	end)
end

return Fallen
