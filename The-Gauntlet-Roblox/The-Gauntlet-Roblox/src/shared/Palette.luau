--!nonstrict
-- Colours sampled from the 2D game (static/style.css and sprite atlases).
local Palette = {}

function Palette.hex(code: string): Color3
	return Color3.fromHex(code)
end

-- Interface (Adventure "woodland" theme in style.css).
Palette.UI = {
	bg = Palette.hex("#171a12"),
	panel = Palette.hex("#282b20"),
	line = Palette.hex("#75775a"),
	ink = Palette.hex("#f0ead7"),
	muted = Palette.hex("#c1c3aa"),
	gold = Palette.hex("#d2b36f"),
	mint = Palette.hex("#b7d49a"),
	red = Palette.hex("#f5a08b"),
	wood = Palette.hex("#25251c"),
	woodLight = Palette.hex("#393b2b"),
	paper = Palette.hex("#d9caa4"),
	paperInk = Palette.hex("#302e22"),
}

-- Ground / mood per art region (average colour of the world-ground sprites).
Palette.Regions = {
	woodland = {
		material = Enum.Material.Grass,
		atmo = { density = 0.34, offset = 0.2, color = Color3.fromRGB(196, 204, 164), decay = Color3.fromRGB(150, 120, 80), glare = 0.35, haze = 1.6 },
		bloom = { intensity = 0.4, size = 26, threshold = 1.5 },
		cc = { brightness = 0.02, contrast = 0.14, saturation = 0.2, tint = Color3.fromRGB(255, 240, 214) },
		sun = { intensity = 0.16, spread = 0.7 },
		clouds = { cover = 0.58, density = 0.5, color = Color3.fromRGB(255, 236, 214) },
		particles = "pollen",
		ground = Palette.hex("#6a772e"),
		accent = Palette.hex("#8a9d61"),
		stone = Palette.hex("#7b7a6b"),
		ambient = Color3.fromRGB(96, 104, 78),
		outdoor = Color3.fromRGB(120, 124, 96),
		fog = Color3.fromRGB(150, 160, 120),
		clock = 16.5,
		brightness = 2,
	},
	ruins = {
		material = Enum.Material.Sand,
		atmo = { density = 0.4, offset = 0.1, color = Color3.fromRGB(214, 184, 140), decay = Color3.fromRGB(160, 100, 60), glare = 0.5, haze = 2.2 },
		bloom = { intensity = 0.45, size = 28, threshold = 1.4 },
		cc = { brightness = 0.02, contrast = 0.18, saturation = 0.1, tint = Color3.fromRGB(255, 226, 190) },
		sun = { intensity = 0.2, spread = 0.8 },
		clouds = { cover = 0.35, density = 0.35, color = Color3.fromRGB(255, 214, 180) },
		particles = "dust",
		ground = Palette.hex("#a99069"),
		accent = Palette.hex("#c5ac7a"),
		stone = Palette.hex("#8c8374"),
		ambient = Color3.fromRGB(110, 98, 84),
		outdoor = Color3.fromRGB(140, 120, 98),
		fog = Color3.fromRGB(170, 150, 120),
		clock = 17.5,
		brightness = 1.8,
	},
	cavern = {
		material = Enum.Material.Slate,
		atmo = { density = 0.55, offset = 0, color = Color3.fromRGB(30, 46, 72), decay = Color3.fromRGB(20, 30, 60), glare = 0, haze = 3 },
		bloom = { intensity = 0.8, size = 30, threshold = 1.1 },
		cc = { brightness = -0.02, contrast = 0.2, saturation = 0.05, tint = Color3.fromRGB(200, 220, 255) },
		sun = { intensity = 0, spread = 0 },
		clouds = { cover = 0, density = 0, color = Color3.fromRGB(0, 0, 0) },
		particles = "spores",
		ground = Palette.hex("#37434b"),
		accent = Palette.hex("#49636c"),
		stone = Palette.hex("#2c4567"),
		ambient = Color3.fromRGB(42, 56, 80),
		outdoor = Color3.fromRGB(50, 66, 94),
		fog = Color3.fromRGB(26, 38, 56),
		clock = 0,
		brightness = 0.8,
	},
	frost = {
		material = Enum.Material.Snow,
		atmo = { density = 0.38, offset = 0.3, color = Color3.fromRGB(206, 224, 244), decay = Color3.fromRGB(150, 170, 200), glare = 0.2, haze = 2 },
		bloom = { intensity = 0.5, size = 28, threshold = 1.4 },
		cc = { brightness = 0.03, contrast = 0.1, saturation = -0.05, tint = Color3.fromRGB(226, 238, 255) },
		sun = { intensity = 0.12, spread = 0.5 },
		clouds = { cover = 0.7, density = 0.6, color = Color3.fromRGB(230, 240, 255) },
		particles = "snow",
		ground = Palette.hex("#c6dbf3"),
		accent = Palette.hex("#e8f3ff"),
		stone = Palette.hex("#8fa8c4"),
		ambient = Color3.fromRGB(130, 150, 176),
		outdoor = Color3.fromRGB(170, 190, 214),
		fog = Color3.fromRGB(200, 218, 240),
		clock = 14,
		brightness = 2.2,
	},
}

Palette.Wood = Palette.hex("#786442")
Palette.Leaf = { Palette.hex("#4f7a3a"), Palette.hex("#5f8f45"), Palette.hex("#3f6a33") }
Palette.Gold = Palette.hex("#ffd166")
Palette.Mint = Palette.hex("#70f09b")

return Palette
