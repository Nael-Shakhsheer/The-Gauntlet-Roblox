--!nonstrict
-- Pure-Luau world layout: places every Adventure area in ONE continuous world.
-- No Roblox APIs here (plain numbers/tables), so it is unit-tested outside Studio
-- (tests/check_layout.luau).
--
--   * Surface areas sit on a grid from the 2D map positions (`pos`), each cell
--     much larger than the areas so trails, wilderness and landmarks fit between.
--   * Neighbouring areas are joined by trails (axis-aligned polylines), using the
--     2D game's exit edges / EXIT_OFFSETS so each trail leaves its area where the
--     2D exit was.
--   * Rootwater cave = a real underground passage reached by two descending ramps
--     (road east edge, clearing west edge).
--   * Briarwatch tower = three stacked floors with internal ramps, entered from
--     the camp and left through a ramp down to the bridge's east bank.
-- Units: studs. Y is up; +X = area x, +Z = area y.
local WorldLayout = {}

local NORMAL = {
	north = { 0, -1 },
	south = { 0, 1 },
	west = { -1, 0 },
	east = { 1, 0 },
}

local function sortedKeys(t)
	local keys = {}
	for key in t do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function newRect(id, kind, cx, cz, w, h, y, spec)
	return {
		id = id,
		kind = kind,
		cx = cx,
		cz = cz,
		w = w,
		h = h,
		y = y,
		left = cx - w / 2,
		right = cx + w / 2,
		top = cz - h / 2,
		bottom = cz + h / 2,
		region = spec.region,
		name = spec.name,
		danger = spec.danger,
		dungeon = spec.dungeon,
		floor = spec.floor,
	}
end

local function edgePoint(r, edge, off)
	if edge == "north" then
		return r.left + r.w * off, r.top
	elseif edge == "south" then
		return r.left + r.w * off, r.bottom
	elseif edge == "west" then
		return r.left, r.top + r.h * off
	end
	return r.right, r.top + r.h * off
end

local function dedupe(points)
	local out = {}
	for _, p in points do
		local last = out[#out]
		if not last or math.abs(last[1] - p[1]) > 0.01 or math.abs(last[2] - p[2]) > 0.01 then
			table.insert(out, { p[1], p[2] })
		end
	end
	return out
end

-- Axis-aligned route: leave p1 along n1, arrive at p2 against n2.
local function elbow(p1, n1, p2, n2, stub)
	local s1 = { p1[1] + n1[1] * stub, p1[2] + n1[2] * stub }
	local s2 = { p2[1] + n2[1] * stub, p2[2] + n2[2] * stub }
	local pts = { p1, s1 }
	local h1, h2 = n1[2] == 0, n2[2] == 0
	if h1 == h2 then
		if h1 then
			local mx = (s1[1] + s2[1]) / 2
			table.insert(pts, { mx, s1[2] })
			table.insert(pts, { mx, s2[2] })
		else
			local mz = (s1[2] + s2[2]) / 2
			table.insert(pts, { s1[1], mz })
			table.insert(pts, { s2[1], mz })
		end
	elseif h1 then
		table.insert(pts, { s2[1], s1[2] })
	else
		table.insert(pts, { s1[1], s2[2] })
	end
	table.insert(pts, s2)
	table.insert(pts, p2)
	return dedupe(pts)
end

local function pathLength(points)
	local total = 0
	for i = 2, #points do
		total += math.abs(points[i][1] - points[i - 1][1]) + math.abs(points[i][2] - points[i - 1][2])
	end
	return total
end

local function addGap(layout, areaId, edge, along)
	layout.gaps[areaId] = layout.gaps[areaId] or {}
	table.insert(layout.gaps[areaId], { edge = edge, along = along })
end

-- Rectangle subtraction for cutting stair/ramp holes out of floor slabs.
-- rect/hole = { minX, maxX, minZ, maxZ }. Returns a list of rects covering rect minus hole.
function WorldLayout.subtract(rect, hole)
	local x1, x2, z1, z2 = rect[1], rect[2], rect[3], rect[4]
	local hx1, hx2, hz1, hz2 = math.max(hole[1], x1), math.min(hole[2], x2), math.max(hole[3], z1), math.min(hole[4], z2)
	if hx1 >= hx2 or hz1 >= hz2 then
		return { rect }
	end
	local out = {}
	if hz1 > z1 then
		table.insert(out, { x1, x2, z1, hz1 }) -- north strip
	end
	if hz2 < z2 then
		table.insert(out, { x1, x2, hz2, z2 }) -- south strip
	end
	if hx1 > x1 then
		table.insert(out, { x1, hx1, hz1, hz2 }) -- west piece
	end
	if hx2 < x2 then
		table.insert(out, { hx2, x2, hz1, hz2 }) -- east piece
	end
	return out
end

function WorldLayout.subtractAll(rect, holes)
	local pieces = { rect }
	for _, hole in holes do
		local nextPieces = {}
		for _, piece in pieces do
			for _, part in WorldLayout.subtract(piece, hole) do
				table.insert(nextPieces, part)
			end
		end
		pieces = nextPieces
	end
	return pieces
end


-- Winding, scenic version of an axis-aligned route: Chaikin-smoothed corners plus a gentle
-- sideways meander that fades to zero at both ends (so it still meets the area edges).
-- Returns a dense list of {x, z} about every `step` studs. Pure/deterministic per key.
function WorldLayout.curve(points, key, step)
	step = step or 8
	local pts = points
	for _ = 1, 3 do
		local out = { pts[1] }
		for i = 1, #pts - 1 do
			local p, q = pts[i], pts[i + 1]
			table.insert(out, { p[1] * 0.75 + q[1] * 0.25, p[2] * 0.75 + q[2] * 0.25 })
			table.insert(out, { p[1] * 0.25 + q[1] * 0.75, p[2] * 0.25 + q[2] * 0.75 })
		end
		table.insert(out, pts[#pts])
		pts = out
	end
	-- cumulative length
	local cum = { 0 }
	for i = 2, #pts do
		cum[i] = cum[i - 1] + math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2)
	end
	local L = cum[#cum]
	if L < 1 then
		return pts
	end
	local h = 11
	for i = 1, #key do
		h = (h * 33 + string.byte(key, i)) % 100003
	end
	local phase1, phase2 = (h % 628) / 100, ((h // 7) % 628) / 100
	local amp = math.clamp(L * 0.09, 8, 36)
	local waves = math.max(1, math.floor(L / 140))
	local count = math.max(2, math.ceil(L / step))
	local out = {}
	local seg = 1
	for n = 0, count do
		local d = L * n / count
		while seg < #pts - 1 and cum[seg + 1] < d do
			seg += 1
		end
		local span = cum[seg + 1] - cum[seg]
		local t = span > 0 and (d - cum[seg]) / span or 0
		local p, q = pts[seg], pts[seg + 1]
		local x, z = p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t
		local tx, tz = q[1] - p[1], q[2] - p[2]
		local tl = math.sqrt(tx * tx + tz * tz)
		if tl > 0 then
			tx, tz = tx / tl, tz / tl
		else
			tx, tz = 1, 0
		end
		local fade = math.clamp(d / 50, 0, 1) * math.clamp((L - d) / 50, 0, 1)
		fade = fade * fade * (3 - 2 * fade)
		local off = fade * amp * (0.7 * math.sin(2 * math.pi * waves * d / L + phase1) + 0.45 * math.sin(2 * math.pi * (waves * 0.53 + 0.4) * d / L + phase2))
		out[#out + 1] = { x - tz * off, z + tx * off }
	end
	return out
end

-- data = { AREAS, LARGE_AREAS, EXIT_OFFSETS, DEFAULT_PX, OPEN_LINKS }
-- opts = { scale, cellPx = {w,h}, caveDepth, floorHeight, slope, trailWidth, rampWidth, stub }
function WorldLayout.compute(data, opts)
	local S = opts.scale
	local cellW, cellH = opts.cellPx[1] * S, opts.cellPx[2] * S
	local depth, floorH, slope = opts.caveDepth, opts.floorHeight, opts.slope
	local stub = opts.stub or 30

	local layout = {
		opts = opts,
		areas = {},
		order = {},
		trails = {}, -- { a, b, y, underground, points }
		ramps = {}, -- { name, kind, x1,z1,y1, x2,z2,y2, width }
		links = {}, -- { a, b, kind } for connectivity checks
		gaps = {}, -- areaId -> { {edge, along} } openings in chamber walls
		floorHoles = {}, -- areaId -> { {minX,maxX,minZ,maxZ} } (stair holes in that floor's slab)
		surfaceHoles = {}, -- holes in the surface slab (cave mouths)
		opens = {}, -- { a, b } surface pairs that touch and flow into each other (no trail)
		skipped = {},
	}
	local areas = layout.areas

	-- 1. Rectangles.
	local ids = sortedKeys(data.AREAS)
	local towerIds = {}
	for _, id in ids do
		local spec = data.AREAS[id]
		local size = data.LARGE_AREAS[id] or data.DEFAULT_PX
		local w, h = size[1] * S, size[2] * S
		if id == "caravan" then
			table.insert(layout.skipped, id) -- opening-only area, not part of the open world
		elseif spec.dungeon == "tower" then
			table.insert(towerIds, id)
		elseif spec.dungeon then
			areas[id] = newRect(id, "cave", spec.pos[1] * cellW, spec.pos[2] * cellH, w, h, -depth, spec)
		else
			areas[id] = newRect(id, "surface", spec.pos[1] * cellW, spec.pos[2] * cellH, w, h, 0, spec)
		end
	end

	-- 2. Which edge of A faces B (union of both sides' declarations).
	local ends = {}
	for _, id in ids do
		if areas[id] then
			for _, e in data.AREAS[id].exits do
				local b, ea, eb = e[1], e[2], e[3]
				if areas[b] then
					ends[id] = ends[id] or {}
					ends[id][b] = ea
					ends[b] = ends[b] or {}
					if not ends[b][id] then
						ends[b][id] = eb
					end
				end
			end
		end
	end

	-- 3. Position of each exit along its edge (0..1): explicit EXIT_OFFSETS, else spread evenly.
	local off = {}
	for _, a in sortedKeys(ends) do
		off[a] = {}
		local byEdge = {}
		for _, b in sortedKeys(ends[a]) do
			local edge = ends[a][b]
			byEdge[edge] = byEdge[edge] or {}
			table.insert(byEdge[edge], b)
		end
		for edge, list in byEdge do
			local horizontalEdge = edge == "north" or edge == "south"
			table.sort(list, function(x, y)
				local kx = horizontalEdge and areas[x].cx or areas[x].cz
				local ky = horizontalEdge and areas[y].cx or areas[y].cz
				if kx == ky then
					return x < y
				end
				return kx < ky
			end)
			local free = {}
			for _, b in list do
				local explicit = data.EXIT_OFFSETS[a .. "|" .. b]
				if explicit then
					off[a][b] = explicit
				else
					table.insert(free, b)
				end
			end
			for i, b in free do
				off[a][b] = #free == 1 and 0.5 or i / (#free + 1)
			end
		end
	end

	-- 3b. Compaction: pull linked surface areas together (open links touch), keep the rest
	-- apart, then move the cave cluster along with the surface it hangs under.
	local original = {}
	for id, r in areas do
		original[id] = { r.cx, r.cz }
	end
	local function moveRect(r, dx, dz)
		r.cx += dx
		r.cz += dz
		r.left += dx
		r.right += dx
		r.top += dz
		r.bottom += dz
	end
	local openSet = {}
	for _, pair in data.OPEN_LINKS or {} do
		local a, b = pair[1], pair[2]
		openSet[a < b and (a .. "|" .. b) or (b .. "|" .. a)] = true
	end
	local function hash(str)
		local h = 7
		for i = 1, #str do
			h = (h * 31 + string.byte(str, i)) % 9973
		end
		return h
	end
	local gapMin, gapVar, unlinked = opts.gapMin or 190, opts.gapVar or 6, opts.unlinkedGap or 100
	local DIR = { east = { 1, 0 }, west = { -1, 0 }, south = { 0, 1 }, north = { 0, -1 } }
	local OPP = { east = "west", west = "east", north = "south", south = "north" }
	local surfaceIds = {}
	for _, id in sortedKeys(areas) do
		if areas[id].kind == "surface" then
			table.insert(surfaceIds, id)
		end
	end
	local constraints, margin = {}, {}
	local function pairKey(a, b)
		return a < b and (a .. "|" .. b) or (b .. "|" .. a)
	end
	for _, a in sortedKeys(ends) do
		for _, b in sortedKeys(ends[a]) do
			local ra, rb = areas[a], areas[b]
			if a < b and ra.kind == "surface" and rb.kind == "surface" then
				local key = pairKey(a, b)
				local ea, eb = ends[a][b], ends[b][a]
				local isOpen = openSet[key] == true
				local gap = isOpen and 0 or gapMin + (hash(key) % gapVar) * 45
				margin[key] = isOpen and 0 or gap * 0.6
				if eb == OPP[ea] then
					table.insert(constraints, { a = a, b = b, ea = ea, gap = gap, open = isOpen, key = key })
				else
					margin[key] = unlinked
				end
			end
		end
	end
	local function marginFor(a, b)
		return margin[pairKey(a, b)] or unlinked
	end
	for _ = 1, 260 do
		for _, c in constraints do
			local ra, rb = areas[c.a], areas[c.b]
			local d = DIR[c.ea]
			local now
			if c.ea == "east" then
				now = rb.left - ra.right
			elseif c.ea == "west" then
				now = ra.left - rb.right
			elseif c.ea == "south" then
				now = rb.top - ra.bottom
			else
				now = ra.top - rb.bottom
			end
			local err = (now - c.gap) * 0.25
			moveRect(ra, d[1] * err, d[2] * err)
			moveRect(rb, -d[1] * err, -d[2] * err)
			-- Cross axis: line the two exit points up (hard for open links, gentle for trails).
			local k = c.open and 0.25 or 0.05
			if d[1] ~= 0 then
				local za = ra.top + ra.h * off[c.a][c.b]
				local zb = rb.top + rb.h * off[c.b][c.a]
				local diff = (za - zb) * k
				moveRect(ra, 0, -diff)
				moveRect(rb, 0, diff)
			else
				local xa = ra.left + ra.w * off[c.a][c.b]
				local xb = rb.left + rb.w * off[c.b][c.a]
				local diff = (xa - xb) * k
				moveRect(ra, -diff, 0)
				moveRect(rb, diff, 0)
			end
		end
		for i = 1, #surfaceIds do
			for j = i + 1, #surfaceIds do
				local ra, rb = areas[surfaceIds[i]], areas[surfaceIds[j]]
				local m = marginFor(ra.id, rb.id)
				local px = math.min(ra.right, rb.right) - math.max(ra.left, rb.left) + m
				local pz = math.min(ra.bottom, rb.bottom) - math.max(ra.top, rb.top) + m
				if px > 0.01 and pz > 0.01 then
					if px < pz then
						local s = (ra.cx < rb.cx or (ra.cx == rb.cx and ra.id < rb.id)) and -1 or 1
						moveRect(ra, s * px / 2, 0)
						moveRect(rb, -s * px / 2, 0)
					else
						local s = (ra.cz < rb.cz or (ra.cz == rb.cz and ra.id < rb.id)) and -1 or 1
						moveRect(ra, 0, s * pz / 2)
						moveRect(rb, 0, -s * pz / 2)
					end
				end
			end
		end
	end
	-- Final snap: open pairs end up exactly flush (shift the second area, then re-check overlaps).
	for _ = 1, 40 do
		for _, c in constraints do
			if c.open then
				local ra, rb = areas[c.a], areas[c.b]
				local d = DIR[c.ea]
				local now
				if c.ea == "east" then
					now = rb.left - ra.right
				elseif c.ea == "west" then
					now = ra.left - rb.right
				elseif c.ea == "south" then
					now = rb.top - ra.bottom
				else
					now = ra.top - rb.bottom
				end
				moveRect(rb, -d[1] * now * 0.5, -d[2] * now * 0.5)
				moveRect(ra, d[1] * now * 0.5, d[2] * now * 0.5)
			end
		end
	end
	-- Caves follow the surface areas they connect to (mean displacement), tunnels stay short.
	do
		local sx, sz, n = 0, 0, 0
		for _, id in surfaceIds do
			if ends[id] then
				for b in ends[id] do
					if areas[b] and areas[b].kind == "cave" then
						sx += areas[id].cx - original[id][1]
						sz += areas[id].cz - original[id][2]
						n += 1
					end
				end
			end
		end
		if n > 0 then
			for id, r in areas do
				if r.kind == "cave" then
					moveRect(r, sx / n, sz / n)
				end
			end
		end
	end

	-- Tower: between the bridge's east bank and the camp, north of their direct trail.
	table.sort(towerIds, function(a, b)
		return data.AREAS[a].floor < data.AREAS[b].floor
	end)
	local camp, bridge = areas.camp, areas.bridge
	if #towerIds > 0 then
		assert(camp and bridge, "tower placement needs the camp and bridge areas")
		local cx = bridge.right + 0.65 * (camp.left - bridge.right)
		local cz = camp.cz - 550 * S
		for _, id in towerIds do
			local spec = data.AREAS[id]
			local size = data.LARGE_AREAS[id] or data.DEFAULT_PX
			areas[id] = newRect(id, "tower", cx, cz, size[1] * S, size[2] * S, (spec.floor - 1) * floorH, spec)
		end
	end
	for _, id in sortedKeys(areas) do
		table.insert(layout.order, id)
	end

	-- 4. Surface <-> surface trails; cave <-> cave tunnels.
	local seen = {}
	for _, a in sortedKeys(ends) do
		for _, b in sortedKeys(ends[a]) do
			local ra, rb = areas[a], areas[b]
			local key = a < b and (a .. "|" .. b) or (b .. "|" .. a)
			if not seen[key] and ra.kind == "surface" and rb.kind == "surface" and openSet[key] then
				seen[key] = true
				table.insert(layout.links, { a = a, b = b, kind = "open" })
				table.insert(layout.opens, { a = a, b = b })
			elseif not seen[key] and ra.kind == rb.kind and (ra.kind == "surface" or ra.kind == "cave") then
				seen[key] = true
				local ea, eb = ends[a][b], ends[b][a]
				local x1, z1 = edgePoint(ra, ea, off[a][b])
				local x2, z2 = edgePoint(rb, eb, off[b][a])
				local underground = ra.kind == "cave"
				local points = elbow({ x1, z1 }, NORMAL[ea], { x2, z2 }, NORMAL[eb], underground and 20 or stub)
				table.insert(layout.trails, {
					a = a,
					b = b,
					y = ra.y,
					underground = underground,
					points = points,
				})
				table.insert(layout.links, { a = a, b = b, kind = underground and "tunnel" or "trail" })
				if underground then
					addGap(layout, a, ea, (ea == "north" or ea == "south") and x1 or z1)
					addGap(layout, b, eb, (eb == "north" or eb == "south") and x2 or z2)
				end
			end
		end
	end

	-- 5. Cave mouths: surface edge -> descending ramp -> corridor -> nearest chamber edge.
	for _, a in sortedKeys(ends) do
		for _, b in sortedKeys(ends[a]) do
			local ra, rb = areas[a], areas[b]
			if ra.kind == "cave" and rb.kind == "surface" then
				local edgeOnSurface = ends[b][a]
				local mx, mz = edgePoint(rb, edgeOnSurface, off[b][a])
				local n = NORMAL[edgeOnSurface]
				local run = depth / slope
				local rx, rz = mx + n[1] * run, mz + n[2] * run
				local half = opts.rampWidth / 2 + 2
				table.insert(layout.ramps, {
					name = a,
					kind = "descent",
					x1 = mx, z1 = mz, y1 = 0,
					x2 = rx, z2 = rz, y2 = -depth,
					width = opts.rampWidth,
				})
				table.insert(layout.surfaceHoles, {
					math.min(mx, rx) - (n[1] ~= 0 and 0 or half),
					math.max(mx, rx) + (n[1] ~= 0 and 0 or half),
					math.min(mz, rz) - (n[2] ~= 0 and 0 or half),
					math.max(mz, rz) + (n[2] ~= 0 and 0 or half),
				})

				-- Nearest chamber edge to the end of the straight stub past the ramp foot.
				rx, rz = rx + n[1] * 20, rz + n[2] * 20
				local best, bestEdge, bestPoint
				for _, edge in { "north", "south", "west", "east" } do
					local t
					if edge == "north" or edge == "south" then
						t = math.clamp((rx - ra.left) / ra.w, 0.12, 0.88)
					else
						t = math.clamp((rz - ra.top) / ra.h, 0.12, 0.88)
					end
					local px, pz = edgePoint(ra, edge, t)
					local d = math.abs(px - rx) + math.abs(pz - rz)
					if not best or d < best then
						best, bestEdge, bestPoint = d, edge, { px, pz }
					end
				end
				-- Keep walking the ramp direction for a stub, then turn into the chamber.
				local points = elbow({ rx - n[1] * 20, rz - n[2] * 20 }, n, bestPoint, NORMAL[bestEdge], 20)
				table.insert(layout.trails, { a = b, b = a, y = -depth, underground = true, points = points })
				table.insert(layout.links, { a = b, b = a, kind = "ramp" })
				addGap(layout, a, bestEdge, (bestEdge == "north" or bestEdge == "south") and bestPoint[1] or bestPoint[2])
			end
		end
	end

	-- 6. Tower: door from the camp, internal stairs, roof ramp down to the bridge.
	if #towerIds > 0 then
		local first = areas[towerIds[1]]
		local last = areas[towerIds[#towerIds]]

		local doorX = first.right - 130 * S
		addGap(layout, first.id, "south", doorX)
		local campX, campZ = edgePoint(camp, "west", 0.3)
		table.insert(layout.trails, {
			a = "camp",
			b = first.id,
			y = 0,
			underground = false,
			points = dedupe({ { campX, campZ }, { doorX, campZ }, { doorX, first.bottom } }),
		})
		table.insert(layout.links, { a = "camp", b = first.id, kind = "trail" })

		for i = 1, #towerIds - 1 do
			local lower, upper = areas[towerIds[i]], areas[towerIds[i + 1]]
			local run = (upper.y - lower.y) / slope
			local x1, x2, z
			if i % 2 == 1 then
				x1 = lower.left + 24
				x2 = x1 + run
				z = lower.top + 28
			else
				x1 = lower.right - 24
				x2 = x1 - run
				z = lower.bottom - 28
			end
			table.insert(layout.ramps, {
				name = lower.id .. "->" .. upper.id,
				kind = "stairs",
				x1 = x1, z1 = z, y1 = lower.y,
				x2 = x2, z2 = z, y2 = upper.y,
				width = 12,
			})
			layout.floorHoles[upper.id] = layout.floorHoles[upper.id] or {}
			table.insert(layout.floorHoles[upper.id], { math.min(x1, x2), math.max(x1, x2), z - 7, z + 7 })
			table.insert(layout.links, { a = lower.id, b = upper.id, kind = "stairs" })
		end

		addGap(layout, last.id, "west", last.cz)
		local run = last.y / slope
		local ex = last.left - run
		table.insert(layout.ramps, {
			name = "tower_exit",
			kind = "descent_out",
			x1 = last.left, z1 = last.cz, y1 = last.y,
			x2 = ex, z2 = last.cz, y2 = 0,
			width = opts.rampWidth,
		})
		local bx, bz = edgePoint(bridge, "east", off.bridge[last.id] or 0.64)
		table.insert(layout.trails, {
			a = last.id,
			b = "bridge",
			y = 0,
			underground = false,
			points = dedupe({ { ex, last.cz }, { ex, bz }, { bx, bz } }),
		})
		table.insert(layout.links, { a = last.id, b = "bridge", kind = "ramp" })
	end

	-- 6b. Winding scenic curves for every overground trail.
	for _, trail in layout.trails do
		if not trail.underground then
			trail.curve = WorldLayout.curve(trail.points, trail.a .. "|" .. trail.b)
		end
	end

	-- 7. Bounds (rects + ramp ends).
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, r in areas do
		minX, maxX = math.min(minX, r.left), math.max(maxX, r.right)
		minZ, maxZ = math.min(minZ, r.top), math.max(maxZ, r.bottom)
	end
	for _, ramp in layout.ramps do
		minX, maxX = math.min(minX, ramp.x1, ramp.x2), math.max(maxX, ramp.x1, ramp.x2)
		minZ, maxZ = math.min(minZ, ramp.z1, ramp.z2), math.max(maxZ, ramp.z1, ramp.z2)
	end
	layout.bounds = { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
	layout.pathLength = pathLength
	return layout
end

-- Which area is a world position in? nil = open wilderness / on a trail / mid-ramp.
function WorldLayout.areaAt(layout, x, y, z)
	local floorH = layout.opts.floorHeight
	local depth = layout.opts.caveDepth
	for _, id in layout.order do
		local r = layout.areas[id]
		if x >= r.left and x <= r.right and z >= r.top and z <= r.bottom then
			if r.kind == "surface" then
				if y > -8 then
					return id
				end
			elseif r.kind == "cave" then
				if y < -depth * 0.5 then
					return id
				end
			elseif r.kind == "tower" then
				local top = (r.floor == 3 or r.floor == nil) and math.huge or r.y + floorH - 6
				if y >= r.y - 6 and y < top then
					return id
				end
			end
		end
	end
	return nil
end

WorldLayout.edgePoint = edgePoint
WorldLayout.pathLength = pathLength
WorldLayout.NORMAL = NORMAL

return WorldLayout
