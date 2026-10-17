--!nocheck
-- luau tests/check_layout.luau  (run from repo root: luau tests/check_layout.luau)
local WorldLayout = require("../src/shared/WorldLayout")
local Adventure = require("../src/shared/Data/Generated/Adventure")

local Config = require("../src/shared/Config")
local Sizes = require("../src/shared/Sizes")
local opts = { gapMin = Config.TRAIL_GAP_MIN, gapVar = Config.TRAIL_GAP_VAR, unlinkedGap = Config.UNLINKED_GAP, scale = Config.WORLD_STUDS_PER_PX, cellPx = Config.WORLD_CELL_PX, caveDepth = Config.CAVE_DEPTH, floorHeight = Config.FLOOR_HEIGHT, slope = Config.RAMP_SLOPE, rampWidth = Config.TRAIL_WIDTH, stub = Config.TRAIL_STUB }
local data = { AREAS = Adventure.AREAS, LARGE_AREAS = Sizes.table(Adventure.AREAS, Adventure.LARGE_AREAS, { 960, 540 }), OPEN_LINKS = Config.OPEN_LINKS, EXIT_OFFSETS = Adventure.EXIT_OFFSETS, DEFAULT_PX = { 960, 540 } }
local L = WorldLayout.compute(data, opts)

local function check(c, m) if not c then error("FAIL: " .. m) end end

-- overlaps (same layer)
local ids = L.order
local n = 0
for i = 1, #ids do
	for j = i + 1, #ids do
		local a, b = L.areas[ids[i]], L.areas[ids[j]]
		local sameLayer = (a.kind == "surface" and b.kind == "surface") or (a.kind == "cave" and b.kind == "cave") or (a.kind == "tower" and b.kind == "tower" and a.y == b.y)
		if sameLayer then
			local ox = math.min(a.right, b.right) - math.max(a.left, b.left)
			local oz = math.min(a.bottom, b.bottom) - math.max(a.top, b.top)
			local isOpen = false
			for _, o in L.opens do
				if (o.a == a.id and o.b == b.id) or (o.a == b.id and o.b == a.id) then isOpen = true end
			end
			if isOpen then
				-- open pairs must touch (gap <= 6) and share a long edge
				if not ((ox >= -6 and oz > 100) or (oz >= -6 and ox > 100)) then print("open pair not flush", a.id, b.id, ox, oz); n += 1 end
				if ox > 1 and oz > 1 then print("open pair overlaps", a.id, b.id); n += 1 end
			elseif ox > -20 and oz > -20 then
				print("overlap/near", a.id, b.id, ox, oz)
				n += 1
			end
		end
	end
end
-- tower vs surface overlap (tower is above ground at floor1 y=0)
local t1 = L.areas.tower_1
for _, id in ids do
	local r = L.areas[id]
	if r.kind == "surface" then
		local ox = math.min(t1.right, r.right) - math.max(t1.left, r.left)
		local oz = math.min(t1.bottom, r.bottom) - math.max(t1.top, r.top)
		if ox > 0 and oz > 0 then print("tower overlaps", id); n += 1 end
	end
end
-- connectivity
local adj = {}
for _, l in L.links do
	adj[l.a] = adj[l.a] or {}; adj[l.b] = adj[l.b] or {}
	table.insert(adj[l.a], l.b); table.insert(adj[l.b], l.a)
end
local seen, q = { home = true }, { "home" }
while #q > 0 do
	local c = table.remove(q, 1)
	for _, nb in adj[c] or {} do
		if not seen[nb] then seen[nb] = true; table.insert(q, nb) end
	end
end
local missing = 0
for _, id in ids do
	if not seen[id] then print("UNREACHED", id); missing += 1 end
end
-- trails axis-aligned
for _, t in L.trails do
	for i = 2, #t.points do
		local p, q2 = t.points[i-1], t.points[i]
		check(math.abs(p[1]-q2[1]) < 0.01 or math.abs(p[2]-q2[2]) < 0.01, "diagonal trail " .. t.a .. "-" .. t.b)
	end
end
-- ramp/hole geometry
local function inside(r, x, z, m) return x > r.left - m and x < r.right + m and z > r.top - m and z < r.bottom + m end
local bad = 0
for _, ramp in L.ramps do
	if ramp.kind == "descent" then
		for _, id in ids do
			local r = L.areas[id]
			if r.kind == "cave" and inside(r, ramp.x2, ramp.z2, 6) then print("ramp bottom inside cave", ramp.name, id); bad += 1 end
		end
	end
end
for _, hole in L.surfaceHoles do
	for _, id in ids do
		local r = L.areas[id]
		if r.kind == "surface" then
			local ox = math.min(hole[2], r.right) - math.max(hole[1], r.left)
			local oz = math.min(hole[4], r.bottom) - math.max(hole[3], r.top)
			if ox > 3 and oz > 3 then print("hole overlaps surface area", id); bad += 1 end
		end
	end
end
-- scenic curves: endpoints match the route, nothing wanders through unrelated areas
local wander = 0
for _, t in L.trails do
	if not t.underground then
		check(t.curve and #t.curve > 2, "missing curve " .. t.a .. "-" .. t.b)
		local p1, pn, c1, cn = t.points[1], t.points[#t.points], t.curve[1], t.curve[#t.curve]
		check(math.abs(p1[1]-c1[1]) < 0.5 and math.abs(p1[2]-c1[2]) < 0.5 and math.abs(pn[1]-cn[1]) < 0.5 and math.abs(pn[2]-cn[2]) < 0.5, "curve ends " .. t.a .. "-" .. t.b)
		for _, c in t.curve do
			for _, id in ids do
				local r = L.areas[id]
				if r.kind == "surface" and id ~= t.a and id ~= t.b and c[1] > r.left + 4 and c[1] < r.right - 4 and c[2] > r.top + 4 and c[2] < r.bottom - 4 then
					print("trail crosses area", t.a, t.b, id); wander += 1; break
				end
			end
		end
	end
end
check(wander == 0, "trails crossing unrelated areas: " .. wander)
-- tunnels must not cut through chambers they do not connect
local cut = 0
for _, t in L.trails do
	if t.underground then
		for i = 2, #t.points do
			local p, q2 = t.points[i-1], t.points[i]
			for _, id in ids do
				local r = L.areas[id]
				if r.kind == "cave" and id ~= t.a and id ~= t.b then
					local x1, x2, z1, z2 = math.min(p[1], q2[1]), math.max(p[1], q2[1]), math.min(p[2], q2[2]), math.max(p[2], q2[2])
					if x2 > r.left + 4 and x1 < r.right - 4 and z2 > r.top + 4 and z1 < r.bottom - 4 then print("tunnel cuts chamber", t.a, t.b, id); cut += 1 end
				end
			end
		end
	end
end
check(cut == 0, "tunnels cutting chambers: " .. cut)
-- every trail point stays near the world bounds
local B = L.bounds
print(("areas=%d trails=%d ramps=%d links=%d"):format(#ids, #L.trails, #L.ramps, #L.links))
print(("bounds x[%d,%d] z[%d,%d] = %dx%d studs"):format(B.minX, B.maxX, B.minZ, B.maxZ, B.maxX-B.minX, B.maxZ-B.minZ))
print("skipped", table.concat(L.skipped, ","))
check(n == 0, "overlaps: " .. n)
check(bad == 0, "geometry problems: " .. bad)
check(missing == 0, "unreached: " .. missing)
print("OK: layout verified")
