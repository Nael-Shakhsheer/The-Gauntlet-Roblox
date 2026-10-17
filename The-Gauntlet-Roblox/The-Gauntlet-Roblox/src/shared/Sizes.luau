--!nonstrict
-- Port-only: wilderness areas are enlarged for big open spaces. Hubs, camps, ruins,
-- dungeons and towers keep their 2D size because their walls/landmarks use absolute 2D px.
-- Feature/enemy/scenery coordinates are scaled by Coord.scaleToArea, so they spread out too.
local Sizes = {}

Sizes.MULT = {
	road = 1.3,
	crossroads = 1.5,
	clearing = 1.5,
	brook = 1.4,
	yard = 1.3,
	hollow = 1.4,
	watch = 1.3,
	border = 1.2,
	fields = 1.5,
	mill = 1.3,
	eastern_threshold = 1.4,
	mill_trail = 1.3,
}

-- areaId -> {widthPx, heightPx}
function Sizes.get(areaId: string, large, default)
	local base = large[areaId] or default
	local m = Sizes.MULT[areaId] or 1
	return { math.round(base[1] * m), math.round(base[2] * m) }
end

-- Full table for WorldLayout (LARGE_AREAS-shaped).
function Sizes.table(areas, large, default)
	local out = {}
	for id in areas do
		out[id] = Sizes.get(id, large, default)
	end
	return out
end

return Sizes
