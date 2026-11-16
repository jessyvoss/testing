-- Fish in Space: economy simulator v2 (dev tool only; the game never uses it).
-- A simulated player fishes the deepest area they can reach, sells, and buys upgrades: whatever opens the next
-- area first (with cheap Bucket / Hook Modification levels in between), then the cheapest upgrade. Once The Void is
-- open they keep buying upgrades that cost under `saveShare` of the rebirth price, save up, rebirth, spend the
-- token on a perk (Head Start first, then Deep Diver), and go again.
-- Assumed: 1.4 s flight + 2 s aiming + sink + reel + 1.5 s per fish; 25 s walk to sell per bucket; rare-fish
-- fights won 78% (Rare) and 62% (Epic) of the time (between an average and a good player).
--   local Sim = require(game.ServerStorage.EconomySim)
--   print(Sim.report(Sim.run(require(game.ReplicatedStorage.FishInSpace.Config))))
local Sim = {}

function Sim.run(C, opts)
	opts = opts or {}
	local U = C.UPGRADES
	local hours = opts.hours or 60
	local saveShare = opts.saveShare or 0.05
	local fightWin = opts.fightWin or { Rare = 0.78, Epic = 0.62 }
	local avg = {}
	for _, f in C.FISH do
		avg[f.rarity] = avg[f.rarity] or { s = 0, n = 0 }
		avg[f.rarity].s += f.value
		avg[f.rarity].n += 1
	end
	for k, v in avg do
		avg[k] = v.s / v.n * (fightWin[k] or 1)
	end
	avg.Junk = 1
	local sizeMult, wsum = 0, 0
	for _, s in C.SIZES do
		sizeMult += s.weight * s.mult
		wsum += s.weight
	end
	sizeMult /= wsum
	local keys = { "tether", "cargo", "throw", "reel", "lure" }
	local lv, perks, rebirths = {}, { headStart = 0, diver = 0, lucky = 0, steady = 0 }, 0
	local function reset()
		for _, k in keys do
			lv[k] = if k == "lure" then 0 else perks.headStart
		end
	end
	reset()
	local function val(key, l)
		local u = U[key]
		return u.values[math.clamp(l + 1, 1, #u.values)]
	end
	local function tier()
		return C.tierOf(lv)
	end
	local function rates()
		local li = tier()
		local L = C.LAYERS[li]
		local maxDepth = val("tether", lv.tether) + C.CAST.rodTip.Y
		local bottom = math.min(L.to, maxDepth)
		local d = (math.max(L.from, 45) + bottom) / 2
		local w = C.layerWeights(li, false, perks.lucky)
		local tw, v = 0, 0
		for r, x in w do
			if r == "Junk" or C.RARITY[r].order <= val("lure", lv.lure) then
				tw += x
				v += x * avg[r]
			end
		end
		local bonus = 1 + math.floor((d - L.from) / C.DEPTH_BONUS.every) * C.DEPTH_BONUS.pct / 100 * (1 + 0.2 * perks.diver)
		local value = v / tw * sizeMult * bonus * C.coinMult(rebirths)
		local sink = U.reel.sink[lv.reel + 1]
		local secs = 1.4 + 2 + d / (C.CAST.sinkSpeed * sink) + (d + 178) / val("reel", lv.reel) + 1.5
		secs += 25 / val("cargo", lv.cargo)
		return value / secs, li
	end
	local function cost(k)
		return U[k].costs[lv[k] + 1]
	end
	local function nextBuy()
		for li = 2, #C.LAYERS do
			local n = C.areaNeeds(li)
			if not (lv.tether >= n.tether and lv.throw >= n.throw and lv.lure >= n.lure) then
				local k
				for _, o in { "tether", "throw", "lure" } do
					if lv[o] < n[o] and (not k or cost(o) < cost(k)) then
						k = o
					end
				end
				for _, o in { "cargo", "reel" } do
					local c = cost(o)
					if c and c < cost(k) * 0.5 then
						k = o
					end
				end
				return k
			end
		end
		local best, bc
		for _, k in keys do
			local c = cost(k)
			if c and (not bc or c < bc) then
				best, bc = k, c
			end
		end
		return best
	end
	local t, coins = 0, 0
	local res = { events = {}, buys = {}, reached = {}, rebirthAt = {} }
	local lastEvent = 0
	local function event(kind, info)
		table.insert(res.events, { t = t, kind = kind, info = info, gap = t - lastEvent })
		lastEvent = t
	end
	while t < hours * 3600 do
		local perSec, li = rates()
		local k = nextBuy()
		local c = k and cost(k)
		local rc = C.rebirthCost(rebirths)
		local wantRebirth = tier() >= C.REBIRTH.needTier and (not c or c > rc * saveShare)
		if wantRebirth then
			local dt = math.max(0, rc - coins) / perSec
			t += dt
			coins = 0
			rebirths += 1
			if perks.headStart < 5 then
				perks.headStart += 1
			elseif perks.diver < 5 then
				perks.diver += 1
			elseif perks.lucky < 5 then
				perks.lucky += 1
			end
			reset()
			table.insert(res.rebirthAt, t)
			event("rebirth", rebirths)
		elseif not c then
			break
		else
			local dt = math.max(0, c - coins) / perSec
			t += dt
			coins += dt * perSec - c
			lv[k] += 1
			table.insert(res.buys, { t = t, k = k, cost = c, wait = dt, perMin = perSec * 60, li = li, rb = rebirths })
			event("buy", k)
			local nt = tier()
			if nt > li then
				event("area", nt)
				if rebirths == 0 and not res.reached[nt] then
					res.reached[nt] = t
				end
			end
		end
	end
	res.total = t
	return res
end

local function median(xs)
	if #xs == 0 then
		return 0
	end
	table.sort(xs)
	return xs[math.ceil(#xs / 2)]
end

function Sim.report(res)
	local out = {}
	out[#out + 1] = ("areas (first run): Nebula %.0f min, Reef %.1f h, Void %.1f h"):format((res.reached[2] or 0) / 60, (res.reached[3] or 0) / 3600, (res.reached[4] or 0) / 3600)
	local rb = {}
	local prev = 0
	for i, at in res.rebirthAt do
		rb[#rb + 1] = ("%d: %.1fh (+%.1f)"):format(i, at / 3600, (at - prev) / 3600)
		prev = at
	end
	out[#out + 1] = "rebirths: " .. table.concat(rb, ", ")
	-- the time between things happening (a purchase, a new area or a rebirth), by stretch of play
	local windows = { { 0, 1 }, { 1, 3 }, { 3, 6 }, { 6, 12 }, { 12, 24 }, { 24, 40 }, { 40, 60 } }
	for _, w in windows do
		local gaps, mx, n = {}, 0, 0
		for _, e in res.events do
			if e.t >= w[1] * 3600 and e.t < w[2] * 3600 then
				table.insert(gaps, e.gap / 60)
				mx = math.max(mx, e.gap / 60)
				n += 1
			end
		end
		if n > 0 then
			out[#out + 1] = ("%2d-%2dh: %3d events, gap median %.1f min, longest %.0f min"):format(w[1], w[2], n, median(gaps), mx)
		end
	end
	return table.concat(out, "\n")
end

return Sim
