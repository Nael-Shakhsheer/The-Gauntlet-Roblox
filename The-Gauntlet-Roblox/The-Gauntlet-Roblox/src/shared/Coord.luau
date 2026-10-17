--!nonstrict
-- 2D game coordinates (px, y grows downward) <-> Roblox world (studs).
--   * Combat scale  STUDS_PER_PX        : ranges, speeds, body sizes.
--   * World scale   WORLD_STUDS_PER_PX  : where areas, features and enemy sites sit.
-- An area's `origin` is its top-left corner at its floor height; area x -> +X, y -> +Z.
local Config = require(script.Parent.Config)

local Coord = {}

function Coord.studs(px: number): number
	return px * Config.STUDS_PER_PX
end

function Coord.px(studs: number): number
	return studs / Config.STUDS_PER_PX
end

function Coord.worldStuds(px: number): number
	return px * Config.WORLD_STUDS_PER_PX
end

-- Area px position -> world position (world scale).
function Coord.toWorld(origin: Vector3, x: number, y: number, height: number?): Vector3
	local s = Config.WORLD_STUDS_PER_PX
	return origin + Vector3.new(x * s, height or 0, y * s)
end

-- adventure.point(): compact (960x540) coordinates scale with larger areas.
function Coord.scaleToArea(x: number, y: number, widthPx: number, heightPx: number): (number, number)
	return x * widthPx / 960, y * heightPx / 540
end

return Coord
