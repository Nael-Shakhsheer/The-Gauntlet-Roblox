--!nonstrict
-- Sound effect hooks. Roblox only plays audio you own or that is publicly approved, so this
-- table ships EMPTY on purpose: paste asset ids ("rbxassetid://123456") from audio YOU upload
-- (Creator Hub > Assets > Audio) and the client plays them at the right moments.
-- Empty id = silent. Volumes are 0..1.
local SoundService = game:GetService("SoundService")

local Sounds = {}

Sounds.IDS = {
	light = "", -- Light attack swing/cast
	special = "", -- Special ability
	ultimate = "", -- Ultimate ability
	hit = "", -- you damaged an enemy
	hurt = "", -- you took damage
	loot = "", -- kill reward / chest
	levelup = "", -- level up
	potion = "", -- potion used
	ui = "", -- shop / dialogue
	telegraph = "", -- enemy attack warning (client may play when close)
}
Sounds.VOLUME = { light = 0.5, special = 0.7, ultimate = 0.9, hit = 0.5, hurt = 0.7, loot = 0.5, levelup = 0.9, potion = 0.6, ui = 0.4, telegraph = 0.3 }

function Sounds.play(name: string)
	local id = Sounds.IDS[name]
	if not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = Sounds.VOLUME[name] or 0.5
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(6, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

return Sounds
