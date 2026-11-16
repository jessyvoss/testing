-- Fish in Space: server. The server decides every catch, sale and upgrade; the client
-- only shows the 2D fishing view and asks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage.FishInSpace
local Config = require(Shared.Config)
local Art = require(Shared.Art)
local FishAura = require(Shared.FishAura)
local Profiles = require(script.Parent.Profiles)
-- analytics funnels (ServerScriptService.Analytics); these only send from the published game's server
local AnalyticsFolder = game:GetService("ServerScriptService"):WaitForChild("Analytics")
local Onboarding = require(AnalyticsFolder:WaitForChild("Onboarding"))
local Funnels = require(AnalyticsFolder:WaitForChild("Funnels"))
local AREA_NAMES = { "Shallows", "Nebula", "Reef", "Void" }
local function field(text: string)
	return { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = text }
end
-- Rebirth funnel: one attempt per rebirth number. Step 1 once The Void is open, step 2 once the cost is affordable.
local function rebirthCheck(player: Player, p)
	if Config.tierOf(p.upgrades) < Config.REBIRTH.needTier then
		return
	end
	local n = p.rebirths + 1
	Funnels.ensure(player, "Rebirth", player.UserId .. ":" .. n, field("Rebirth - " .. n))
	if p.coins >= Config.rebirthCost(p.rebirths) then
		Funnels.step(player, "Rebirth", 2)
	end
end
-- BADGES (ids in Config.BADGES; 0 = not created yet). Each is awarded once: we check the player doesn't already
-- have it, and remember per player per server so repeat moments don't call the badge service again.
local BadgeService = game:GetService("BadgeService")
local badgeDone: { [Player]: { [string]: boolean } } = {}
local function award(player: Player, key: string)
	local id = Config.BADGES and Config.BADGES[key]
	if not id or id == 0 then
		return
	end
	badgeDone[player] = badgeDone[player] or {}
	if badgeDone[player][key] then
		return
	end
	badgeDone[player][key] = true
	task.spawn(function()
		local okHas, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, id)
		if okHas and has then
			return
		end
		local ok, err = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, id)
		if not ok then
			badgeDone[player][key] = nil -- (try again next time)
			warn("Badge " .. key .. ": " .. tostring(err))
		end
	end)
end
Players.PlayerRemoving:Connect(function(player)
	badgeDone[player] = nil
end)
-- badges a returning player already earned before badges existed
local function awardEarned(player: Player, p)
	if p.tutorialDone then
		award(player, "WELCOME")
	end
	if (p.stats.caught or 0) > 0 then
		award(player, "FIRST_CATCH")
	end
	if (p.rebirths or 0) > 0 then
		award(player, "REBORN")
	end
	if (p.rebirths or 0) > 0 or Config.tierOf(p.upgrades) >= 4 then
		award(player, "VOID")
	end
	for id in p.catalog do
		local f = Config.BY_ID[id]
		if f and f.rarity == "Epic" then
			award(player, "EPIC")
			break
		end
	end
end

-- ZorpQuest funnel: each quest carries its own id (saved with it), so a quest picks up again after a rejoin
local function questSession(player: Player, q)
	if not q.sid then
		q.sid = HttpService:GenerateGUID(false)
	end
	Funnels.ensure(player, "ZorpQuest", q.sid, field("Rarity - " .. Config.BY_ID[q.id].rarity))
end

local Remotes = Shared.Remotes
local FishRF: RemoteFunction = Remotes.Fish
local ShopRF: RemoteFunction = Remotes.Shop
local CatalogRF: RemoteFunction = Remotes.Catalog
local QuestRF: RemoteFunction = Remotes.Quest
local State: RemoteEvent = Remotes.State

local World = workspace:WaitForChild("World")
local casts: { [Player]: any } = {}
-- Rare catches are announced to the server too, but at most once a minute per player (a Reef session would flood it)
local lastRareShout: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(player)
	lastRareShout[player] = nil
end)
local serverLuckUntil = 0

---------------------------------------------------------------- helpers

local function hasPass(player: Player, key: string): boolean
	return player:GetAttribute("Pass_" .. key) == true
end

local function tierMult(p): number
	return Config.tierMult(p.upgrades) -- by the deepest area you can fish in
end

local function cargoCap(player: Player, p): number
	local cap = Config.upgradeValue("cargo", p.upgrades.cargo)
	if hasPass(player, "BIG_BUCKET") then
		cap = math.floor(cap * (1 + Config.BIG_BUCKET_BONUS))
	end
	return cap
end

local function hookCap(player: Player, p): number
	-- one fish per cast (the +1 Hook pass adds a second)
	return 1 + (if hasPass(player, "PLUS_HOOK") then 1 else 0)
end

-- official group membership (fresh from GroupService, so joining mid-game counts after a re-check)
local GroupService = game:GetService("GroupService")
local lastGroupCheck: { [Player]: number } = {}
local function checkGroup(player: Player)
	lastGroupCheck[player] = os.clock()
	local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
	local member = false
	if ok and groups then
		for _, g in groups do
			if g.Id == Config.GROUP_ID then
				member = true
				break
			end
		end
	else
		local ok2, res = pcall(player.IsInGroup, player, Config.GROUP_ID)
		member = ok2 and res == true
	end
	player:SetAttribute("InGroup", member)
	return member
end
Players.PlayerRemoving:Connect(function(player)
	lastGroupCheck[player] = nil
end)

local function fishValue(player: Player, entry): number
	local f = Config.BY_ID[entry.id]
	local s = Config.SIZES[entry.size]
	local v = f.value * s.mult * (1 + (entry.bonus or 0) / 100) -- size, then the depth bonus
	if hasPass(player, "VIP") then
		v *= 1 + Config.VIP_SELL_BONUS
	end
	if hasPass(player, "DOUBLE_COINS") then
		v *= 2
	end
	if hasPass(player, "GOD_ROD") then
		v *= 1 + Config.GOD_ROD_VALUE
	end
	if player:GetAttribute("InGroup") then
		v *= 1 + Config.GROUP_COIN_BONUS
	end
	local prof = Profiles.get(player)
	if prof then
		v *= Config.coinMult(prof.rebirths) -- +25% per rebirth
	end
	return math.max(1, math.floor(v + 0.5))
end

local function cargoValue(player: Player, p): number
	local t = 0
	for _, c in p.cargo do
		t += fishValue(player, c)
	end
	return t
end

local function luckActive(p): boolean
	return os.time() < math.max(p.luckUntil, serverLuckUntil)
end

-- What the client needs to draw menus. Small and safe to send often.
local function snapshot(player: Player)
	local p = Profiles.get(player)
	if not p then
		return nil
	end
	local passes = {}
	for key in Config.PASSES do
		passes[key] = hasPass(player, key)
	end
	return {
		coins = p.coins,
		upgrades = table.clone(p.upgrades),
		cargo = p.cargo,
		cargoCap = cargoCap(player, p),
		cargoValue = cargoValue(player, p),
		hookCap = hookCap(player, p),
		catalog = p.catalog,
		stats = p.stats,
		world2 = p.world2,
		passes = passes,
		luckUntil = math.max(p.luckUntil, serverLuckUntil),
		now = os.time(),
		held = player:GetAttribute("Holding"),
		tutorialDone = p.tutorialDone,
		questsUnlocked = p.questsUnlocked,
		settings = p.settings,
		rebirths = p.rebirths,
		tokens = p.tokens,
		perks = p.perks,
		rebirthCost = Config.rebirthCost(p.rebirths),
		starterLeft = if p.starterBought then 0 else math.max(0, Config.STARTER.seconds - (p.playSeconds or 0)),
		starterLine = p.starterLine,
		fishQuest = p.fishQuest,
	}
end

-- numbers the lobby leaderboards rank by (kept on the player as attributes)
local function setBoardStats(player: Player, p)
	local unique, levels = 0, 0
	for id in p.catalog do
		if Config.BY_ID[id] then
			unique += 1
		end
	end
	for _, lv in p.upgrades do
		levels += tonumber(lv) or 0
	end
	player:SetAttribute("TotalCaught", p.stats.caught)
	player:SetAttribute("RareCaught", p.stats.rare or 0)
	player:SetAttribute("Earned", p.earned)
	player:SetAttribute("Biggest", p.stats.biggest or 0)
	-- overall fishing progression: species discovered, gear upgraded and fish caught
	player:SetAttribute("FisherScore", unique * 100 + levels * 50 + p.stats.caught)
end

local function push(player: Player)
	local p = Profiles.get(player)
	if p then
		setBoardStats(player, p)
	end
	State:FireClient(player, { type = "profile", profile = snapshot(player) })
end

---------------------------------------------------------------- quests

local function rollQuests(p, kind: string, period: number)
	local list = Config.QUESTS[kind]
	local count = Config.QUESTS.dailyCount
	local rng = Random.new(period * 31 + 1)
	-- only quests for areas you've unlocked (no "catch an Uncommon" while you're still in the Shallows)
	local tier = Config.tierOf(p.upgrades)
	local pool = {}
	for _, q in list do
		if (q.minTier or 1) <= tier then
			table.insert(pool, q)
		end
	end
	local out = {}
	local mult = tierMult(p)
	for _ = 1, math.min(count, #pool) do
		local q = table.remove(pool, rng:NextInteger(1, #pool))
		local goal = if q.scaleGoal then math.floor(q.goal * mult) else q.goal
		table.insert(out, { id = q.id, kind = kind, stat = q.stat, text = q.text:format(goal), goal = goal, progress = 0, coins = math.floor(q.coins * mult), claimed = false })
	end
	return out
end

local function ensureQuests(p)
	local day = Profiles.today()
	local q = p.quests
	if q.day ~= day or typeof(q.daily) ~= "table" then
		q.day = day
		q.daily = rollQuests(p, "daily", day)
	end
	q.weekly, q.week = nil, nil -- (weekly quests were removed)
end

local function track(player: Player, stat: string, n: number)
	local p = Profiles.get(player)
	if not p or n <= 0 then
		return
	end
	ensureQuests(p)
	local changed = false
	for _, list in { p.quests.daily } do
		for _, q in list do
			if q.stat == stat and q.progress < q.goal then
				q.progress = math.min(q.goal, q.progress + n)
				changed = true
				if q.progress >= q.goal then
					State:FireClient(player, { type = "questReady", text = q.text })
				end
			end
		end
	end
	if changed then
		Profiles.markDirty(player)
	end
end

QuestRF.OnServerInvoke = function(player: Player, req)
	local p = Profiles.get(player)
	if not p or typeof(req) ~= "table" then
		return nil
	end
	ensureQuests(p)
	if req.action == "claim" then
		for _, list in { p.quests.daily } do
			for _, q in list do
				if q.id == req.id and q.progress >= q.goal and not q.claimed then
					q.claimed = true
					Profiles.addCoins(player, q.coins)
					Profiles.markDirty(player)
					push(player)
					return { ok = true, coins = q.coins, daily = p.quests.daily }
				end
			end
		end
		return { ok = false, daily = p.quests.daily }
	end
	local now = os.time()
	return { daily = p.quests.daily, dailyResetIn = 86400 - now % 86400 }
end

---------------------------------------------------------------- fishing

local function inFishZone(player: Player): (boolean, number?)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	-- on the fishing dock (a little slack for lag)
	local facing = Config.fishFacing(root.Position, 2)
	if facing then
		return true, facing
	end
	return false
end

local byRarity = {}
for _, f in Config.FISH do
	byRarity[f.rarity] = byRarity[f.rarity] or {}
	table.insert(byRarity[f.rarity], f)
end
byRarity.Junk = Config.JUNK

local function pickWeighted(rng, weights)
	local total = 0
	for _, w in weights do
		total += w
	end
	local r = rng:NextNumber() * total
	for k, w in weights do
		r -= w
		if r <= 0 then
			return k
		end
	end
	return next(weights)
end

local sizeWeights = {}
for i, s in Config.SIZES do
	sizeWeights[i] = s.weight
end

-- Each player has one sea of fish that stays between casts (the fish are always there).
-- A caught fish is replaced by a new one somewhere else in its layer. The sea is rebuilt only
-- when your Line Length or a luck boost changes what lives within reach.
local seas: { [Player]: any } = {}

-- luck = 1 while a Rare Boost is on, plus 10 x the Lucky Charm perk level
local function layerWeights(li: number, luck: number)
	return Config.layerWeights(li, luck % 10 >= 1, luck // 10)
end

-- Where the hook is at a given depth: it lands at your Distance Throw, sinks almost straight down (drifting
-- slowly back toward the dock), and once the line is all out it swings in on the line toward the dock.
local function hookX(depth: number, maxLen: number, reach: number): number
	local tip = Config.CAST.rodTip
	local below = depth - tip.Y -- vertical distance from the rod tip
	local arc = tip.X + math.sqrt(math.max(0, maxLen * maxLen - below * below))
	-- a cast lands at your Distance Throw (same as FishingView.launch)
	local drop = tip.X + reach - depth * (Config.CAST.drift / Config.CAST.sinkSpeed)
	return math.min(arc, drop)
end

local function newEntry(rng, i: number, li: number, maxDepth: number, luck: number, maxLen: number, reach: number, others: { any }?)
	local layer = Config.LAYERS[li]
	local rarity = pickWeighted(rng, layerWeights(li, luck))
	local list = byRarity[rarity]
	local f = list[rng:NextInteger(1, #list)]
	local lo = math.max(layer.from + 12, Config.CAST.fishMinDepth or 6)
	local hi = math.min(layer.to - 12, maxDepth - 10)
	-- a spot along the hook's path, kept apart from the other fish (best of a few tries)
	-- Rarer layers live farther out: until your Distance Throw reaches a layer's throw level, its fish sit past your
	-- hook (shown, out of reach). Once you can reach them they spread over the whole stretch between the dock and
	-- where your hook sinks, so there are still fish to catch on the way back in. They're never in the drop path
	-- itself: you have to steer or reel to reach a fish.
	local throwVals = Config.UPGRADES.throw.values
	local req = layer.throwLevel or 0
	local far = reach < (throwVals[req + 1] or 0)
	local mv = Config.MOVE[rarity] or {}
	local wantMoves = rng:NextNumber() < (mv.share or Config.CAST.movingShare)
	-- room for the fish's sway (and a bit of its body) so it never drifts into the hook's drop path
	local clear = (Config.CAST.pathClear or 30) + (mv.drift or 0) + 10
	local function gateX(d)
		if req <= 0 then
			return layer.out or 30
		end
		return hookX(d, math.huge, throwVals[req]) - 15 -- just past where the previous level's hook sinks
	end
	local depth, x, bestGap, moves = lo, gateX(lo) + 40, -1, false
	for _ = 1, 20 do
		local d = if hi > lo then rng:NextNumber(lo, hi) else lo
		local gx = gateX(d)
		local px, mv
		if far then
			px = math.max(gx, hookX(d, maxLen, reach) + 25) + rng:NextNumber(10, 180)
			mv = false
		else
			local hiX = hookX(d, maxLen, reach) - clear
			local lowX = Config.LAYERS[1].out or 30 -- the whole left side, out from the dock
			local room = hiX - lowX
			if room <= 0 then
				continue -- no room beside the path at this depth
			end
			mv = wantMoves and room > 160 -- patrolling fish need room to swim without crossing the path
			if mv then
				hiX -= 60
				room -= 60
			end
			px = hiX - rng:NextNumber(0, room)
			-- where the line has run out the hook swings in on a circle: stay inside that too
			local tip = Config.CAST.rodTip
			if (Vector2.new(px, d) - tip).Magnitude > maxLen - clear - (if mv then 60 else 0) then
				continue
			end
		end
		local gap = math.huge
		for _, o in others or {} do
			if o.i ~= i then
				gap = math.min(gap, (Vector2.new(o.x, o.depth) - Vector2.new(px, d)).Magnitude)
			end
		end
		if gap > bestGap then
			depth, x, bestGap, moves = d, px, gap, mv
		end
		if gap >= (Config.CAST.fishGap or 60) then
			break
		end
	end
	-- every fish has a fixed spot in its layer's box (further out and deeper for rarer layers)
	return {
		i = i,
		id = f.id,
		size = pickWeighted(rng, sizeWeights),
		depth = depth,
		x = x, -- around the hook's path, mostly just inside it (where a reel-in passes too)
		far = far, -- past your Distance Throw: shown, but out of reach
		moves = moves,
		layer = li,
		seed = rng:NextInteger(1, 1e6),
	}
end

local function buildPool(player: Player, p)
	local maxLen = Config.upgradeValue("tether", p.upgrades.tether)
	local maxDepth = maxLen + Config.CAST.rodTip.Y
	local luck = (if luckActive(p) then 1 else 0) + 10 * (p.perks.lucky or 0) -- Rare Boost + Lucky Charm
	local reach = math.max(Config.upgradeValue("throw", p.upgrades.throw or 0), Config.CAST.minReach or 0)
	-- Studio only, for recording the trailer: the player attribute TrailerVoid stocks only The Void (more fish there),
	-- so a cast sinks straight past the empty upper areas to the Epics
	local trailer = game:GetService("RunService"):IsStudio() and player:GetAttribute("TrailerVoid") == true
	local sig = maxLen .. ":" .. luck .. ":" .. reach .. (if trailer then ":trailer" else "")
	local sea = seas[player]
	if sea and sea.sig == sig then
		return sea.pool, maxLen
	end
	local rng = Random.new()
	local pool = {}
	for li, layer in Config.LAYERS do
		if layer.from < maxDepth - 4 and (not trailer or li == #Config.LAYERS) then
			for _ = 1, (if trailer then 10 else layer.count or Config.CAST.poolPerLayer) do
				table.insert(pool, newEntry(rng, #pool + 1, li, maxDepth, luck, maxLen, reach, pool))
			end
		end
	end
	seas[player] = { sig = sig, pool = pool, maxDepth = maxDepth, luck = luck, rng = rng, maxLen = maxLen, reach = reach }
	return pool, maxLen
end

-- a caught fish leaves the sea; a new one turns up elsewhere in the same layer
local function restock(player: Player, idx: number)
	local sea = seas[player]
	local old = sea and sea.pool[idx]
	if old then
		sea.pool[idx] = newEntry(sea.rng, idx, old.layer, sea.maxDepth, sea.luck, sea.maxLen, sea.reach, sea.pool)
	end
end

local function addToCatalog(player: Player, p, entry): boolean
	local e = p.catalog[entry.id]
	if not e then
		p.catalog[entry.id] = { best = entry.size, count = 1 }
		return true
	end
	e.count += 1
	if entry.size > e.best then
		e.best = entry.size
		if player:GetAttribute("Holding") == entry.id then
			player:SetAttribute("HoldingSize", e.best)
		end
	end
	return false
end

FishRF.OnServerInvoke = function(player: Player, req)
	local p = Profiles.get(player)
	if not p or typeof(req) ~= "table" then
		return { ok = false, message = "Still loading" }
	end
	if req.action == "start" then
		local ok, facing = inFishZone(player)
		if not ok then
			return { ok = false, message = "Walk to the fishing dock to fish" }
		end
		if #p.cargo >= cargoCap(player, p) then
			return { ok = false, message = "Bucket full! Sell your fish to Zorp", full = true }
		end
		local pool, maxLen = buildPool(player, p)
		local token = HttpService:GenerateGUID(false)
		casts[player] = { token = token, t0 = os.clock(), pool = pool, cap = hookCap(player, p) }
		local reply = { ok = true, token = token, pool = pool, maxLen = maxLen, hookCap = hookCap(player, p), reel = Config.upgradeValue("reel", p.upgrades.reel), reach = Config.upgradeValue("throw", p.upgrades.throw or 0), baitMax = if hasPass(player, "GOD_ROD") then 4 else Config.baitMax(p.upgrades.lure), sink = Config.UPGRADES.reel.sink[math.clamp((p.upgrades.reel or 0) + 1, 1, #Config.UPGRADES.reel.sink)], facing = facing, luck = luckActive(p) }
		if luckActive(p) then
			reply.baitMax = math.min(4, reply.baitMax + 1)
			reply.boost = true
		end
		if hasPass(player, "GOD_ROD") then
			reply.reel *= Config.GOD_ROD_SPEED
			reply.sink *= Config.GOD_ROD_SPEED
			reply.godRod = true
		end
		-- the rare-fish fight: a wider catch zone with the God Rod and the Steady Hands perk
		reply.fightZone = (1 + 0.1 * (p.perks.steady or 0)) * (if hasPass(player, "GOD_ROD") then 1.3 else 1)
		Onboarding.markStep(player, 2) -- First Cast
		return reply
	elseif req.action == "finish" then
		local c = casts[player]
		casts[player] = nil
		if not c or req.token ~= c.token or typeof(req.hooked) ~= "table" then
			return { ok = false, caught = {} }
		end
		local elapsed = os.clock() - c.t0
		p.stats.casts += 1
		track(player, "cast", 1)
		local caught = {}
		local seen = {}
		local space = cargoCap(player, p) - #p.cargo
		local baitMax = if hasPass(player, "GOD_ROD") then 4 else Config.baitMax(p.upgrades.lure)
		if luckActive(p) then
			baitMax = math.min(4, baitMax + 1) -- Rare Boost: one rarity above your bait bites too
		end
		for _, idx in req.hooked do
			local entry = typeof(idx) == "number" and c.pool[idx]
			if entry and Config.RARITY[Config.BY_ID[entry.id].rarity].order > baitMax then
				entry = nil -- too rare for this bait: it never bit
			end
			-- deep fish take time to reach: the swing can't get there instantly
			if entry and not seen[idx] and #caught < c.cap and elapsed >= 0.6 + entry.depth / 600 then
				seen[idx] = true
				restock(player, idx)
				if space > 0 then
					space -= 1
					local bonus = math.floor(Config.depthBonus(entry.id, entry.depth) * (1 + 0.2 * (p.perks.diver or 0))) -- Deep Diver perk
					local item = { id = entry.id, size = entry.size, bonus = bonus }
					table.insert(p.cargo, item)
					local f = Config.BY_ID[entry.id]
					local isNew = addToCatalog(player, p, entry)
					local value = fishValue(player, item)
					p.stats.caught += 1
					if Config.RARITY[f.rarity].order >= 3 then
						p.stats.rare = (p.stats.rare or 0) + 1
					end
					if value > p.stats.biggest then
						p.stats.biggest = value
					end
					track(player, "catch", 1)
					local order = Config.RARITY[f.rarity].order
					if order >= 4 then
						award(player, "EPIC") -- Epic Angler
					end
					if order >= 2 then
						track(player, "uncommon", 1)
					end
					if order >= 3 then
						track(player, "rare", 1)
					end
					if entry.size == #Config.SIZES then
						track(player, "huge", 1)
					end
					if isNew then
						track(player, "discover", 1)
					end
					local q = p.fishQuest
					if q and q.id == entry.id and q.have < q.need then
						q.have += 1
						State:FireClient(player, { type = "questFish", id = entry.id, have = q.have, need = q.need })
						if q.have >= q.need then
							questSession(player, q)
							Funnels.step(player, "ZorpQuest", 2) -- Quest Fish Caught
						end
					end
					if isNew then
						local unique = 0
						for _, ff in Config.FISH do
							if p.catalog[ff.id] then
								unique += 1
							end
						end
						if unique == #Config.FISH and Config.BY_ID[entry.id].rarity ~= "Junk" then
							for _, other in Players:GetPlayers() do
								State:FireClient(other, { type = "allFish", who = player.DisplayName })
							end
						end
					end
					table.insert(caught, { id = entry.id, size = entry.size, value = value, new = isNew, bonus = bonus })
					local shout = order >= Config.SHOUT_MIN_ORDER or (order >= 3 and entry.size == #Config.SIZES)
					if not shout and order >= 3 then
						local now = os.clock()
						if (lastRareShout[player] or -math.huge) < now - 60 then
							lastRareShout[player] = now
							shout = true
						end
					end
					if shout then
						-- a big catch: the whole server hears about it
						for _, other in Players:GetPlayers() do
							State:FireClient(other, { type = "epic", who = player.DisplayName, id = entry.id, size = entry.size, value = value })
						end
					end
				else
					table.insert(caught, { id = entry.id, size = entry.size, lost = true })
				end
			end
		end
		player:SetAttribute("TotalCaught", p.stats.caught)
		Profiles.markDirty(player)
		push(player)
		for _, got in caught do
			if not got.lost then
				Onboarding.markStep(player, 3) -- First Fish Caught
				award(player, "FIRST_CATCH")
				break
			end
		end
		return { ok = true, caught = caught }
	elseif req.action == "cancel" then
		casts[player] = nil
		return { ok = true }
	elseif req.action == "release" then
		local i = tonumber(req.index)
		if i and p.cargo[i] then
			table.remove(p.cargo, i)
			Profiles.markDirty(player)
			push(player)
		end
		return { ok = true }
	end
	return { ok = false }
end

---------------------------------------------------------------- selling, upgrades, world 2

local merchant = World:FindFirstChild("Merchant", true) -- the cat: runs the upgrade shop
-- you sell your fish to Zorp (one at each dock)
local function nearSeller(player: Player): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	for _, z in World:GetDescendants() do
		if z.Name == "QuestAlien" and z:IsA("Model") and (root.Position - z:GetPivot().Position).Magnitude < 18 then
			return true
		end
	end
	return false
end

local function sellAll(player: Player)
	local p = Profiles.get(player)
	if not p or #p.cargo == 0 then
		return { ok = false, message = "Your bucket is empty" }
	end
	local total = cargoValue(player, p)
	local count = #p.cargo
	p.cargo = {}
	p.earned += total
	Profiles.addCoins(player, total)
	track(player, "sell", total)
	player:SetAttribute("Earned", p.earned)
	Profiles.markDirty(player)
	push(player)
	Onboarding.markStep(player, 4) -- First Sale
	rebirthCheck(player, p)
	return { ok = true, coins = total, count = count, message = ("Sold %d fish for %d coins"):format(count, total) }
end

ShopRF.OnServerInvoke = function(player: Player, req)
	local p = Profiles.get(player)
	if not p or typeof(req) ~= "table" then
		return { ok = false, message = "Still loading" }
	end
	if req.action == "sell" then
		if not nearSeller(player) and not hasPass(player, "AUTO_SELL") then
			return { ok = false, message = "Visit Zorp at a dock to sell (or get Auto-Sell)" }
		end
		return sellAll(player)
	elseif req.action == "upgrade" then
		local u = Config.UPGRADES[req.key]
		if not u then
			return { ok = false, message = "Unknown upgrade" }
		end
		local level = p.upgrades[req.key]
		local cost = u.costs[level + 1]
		if not cost then
			return { ok = false, message = "Already maxed" }
		end
		if p.coins < cost then
			return { ok = false, message = ("Need %d more coins"):format(cost - p.coins) }
		end
		p.coins -= cost
		p.upgrades[req.key] = level + 1
		player:SetAttribute("Coins", p.coins)
		Profiles.markDirty(player)
		push(player)
		Funnels.step(player, "Upgrades", 2) -- Bought an Upgrade
		Onboarding.markStep(player, 5) -- First Upgrade
		if Config.tierOf(p.upgrades) >= 2 then
			Onboarding.markStep(player, 7) -- Reached Nebula Drift
		end
		if Config.tierOf(p.upgrades) >= 4 then
			award(player, "VOID") -- Into The Void
		end
		rebirthCheck(player, p)
		return { ok = true, message = u.name .. " upgraded!" }
	elseif req.action == "groupCheck" then
		if os.clock() - (lastGroupCheck[player] or 0) < 3 then
			return { ok = false, message = "Checking... try again in a moment" }
		end
		local member = checkGroup(player)
		push(player)
		if member then
			return { ok = true, message = ("Group bonus active! +%d%% coins"):format(Config.GROUP_COIN_BONUS * 100) }
		end
		return { ok = false, message = "Join the group to get the bonus" }
	elseif req.action == "world2" then
		if not Config.WORLD2_OPEN then
			return { ok = false, message = "World 2 is under construction. Check back soon!" }
		end
		if p.world2 then
			return { ok = false, message = "World 2 is already unlocked" }
		end
		if p.coins < Config.WORLD2_COST then
			return { ok = false, message = ("Need %d more coins"):format(Config.WORLD2_COST - p.coins) }
		end
		p.coins -= Config.WORLD2_COST
		p.world2 = true
		player:SetAttribute("Coins", p.coins)
		Profiles.markDirty(player)
		push(player)
		return { ok = true, message = "World 2 unlocked! It opens in a future update." }
	elseif req.action == "groupJoined" then
		-- the Join the Group sign: welcome coins, once, after checking the player really is in the group
		local gid = Config.GROUP and Config.GROUP.id or 0
		if gid == 0 then
			return { ok = false, message = "Group not set up yet" }
		end
		if p.groupGift then
			return { ok = true, already = true }
		end
		local member = false
		local okG, groups = pcall(function()
			return game:GetService("GroupService"):GetGroupsAsync(player.UserId)
		end)
		if okG and groups then
			for _, g in groups do
				if g.Id == gid then
					member = true
				end
			end
		end
		if not member then
			return { ok = false, message = "Join the group to get your welcome gift" }
		end
		p.groupGift = true
		Profiles.addCoins(player, Config.GROUP.joinGift)
		Profiles.markDirty(player)
		push(player)
		return { ok = true, gift = Config.GROUP.joinGift }
	elseif req.action == "rebirth" then
		if Config.tierOf(p.upgrades) < Config.REBIRTH.needTier then
			return { ok = false, message = "Unlock The Void first" }
		end
		local cost = Config.rebirthCost(p.rebirths)
		if p.coins < cost then
			return { ok = false, message = ("Need %d more coins"):format(cost - p.coins) }
		end
		p.rebirths += 1
		p.tokens += 1
		p.coins = 0
		p.cargo = {}
		for key in p.upgrades do
			p.upgrades[key] = 0
		end
		-- Head Start perk: begin with some levels already bought
		local head = 5 * (p.perks.headStart or 0)
		for _, key in { "cargo", "tether", "throw", "reel" } do
			p.upgrades[key] = math.min(head, #Config.UPGRADES[key].costs)
		end
		seas[player] = nil
		player:SetAttribute("Coins", p.coins)
		player:SetAttribute("Rebirths", p.rebirths)
		Profiles.markDirty(player)
		for _, other in Players:GetPlayers() do
			State:FireClient(other, { type = "rebirth", who = player.DisplayName, n = p.rebirths })
		end
		push(player)
		Funnels.ensure(player, "Rebirth", player.UserId .. ":" .. p.rebirths, field("Rebirth - " .. p.rebirths))
		Funnels.step(player, "Rebirth", 3) -- Rebirthed
		award(player, "REBORN")
		Funnels.finish(player, "Rebirth")
		return { ok = true, message = ("REBIRTH %d! Coins x%.2f forever, +1 perk token"):format(p.rebirths, Config.coinMult(p.rebirths)) }
	elseif req.action == "perk" then
		local pk = Config.PERKS[req.key]
		if not pk then
			return { ok = false, message = "Unknown perk" }
		end
		local lv = p.perks[req.key] or 0
		if lv >= pk.max then
			return { ok = false, message = pk.name .. " is maxed" }
		end
		if p.tokens < 1 then
			return { ok = false, message = "You need a rebirth token (rebirth to earn one)" }
		end
		p.tokens -= 1
		p.perks[req.key] = lv + 1
		seas[player] = nil -- (Lucky Charm changes what spawns)
		Profiles.markDirty(player)
		push(player)
		return { ok = true, message = pk.name .. " upgraded!" }
	elseif req.action == "settings" then
		p.settings = Profiles.cleanSettings(req.settings)
		Profiles.markDirty(player)
		return { ok = true }
	elseif req.action == "tutorialDone" then
		p.tutorialDone = true
		Onboarding.markStep(player, 6) -- Tutorial Completed
		award(player, "WELCOME")
		Profiles.markDirty(player)
		push(player) -- (the starter quest appears right after the tutorial)
		return { ok = true }
	elseif req.action == "profile" then
		return { ok = true, profile = snapshot(player) }
	end
	return { ok = false }
end

---------------------------------------------------------------- catalog: hold your biggest catch

-- arms up over the head while holding a fish: the pose itself is applied on every client by
-- StarterPlayerScripts.HoldPose (it overrides the shoulder joints each frame while a character has a HeldFish).
-- This only undoes the older server-side pose if a character still has it.
local function setArmsUp(char: Model?, _up: boolean)
	if not char then
		return
	end
	for _, name in { "RightShoulder", "LeftShoulder" } do
		local arm = char:FindFirstChild(if name == "RightShoulder" then "RightUpperArm" else "LeftUpperArm")
		local joint = arm and arm:FindFirstChild(name)
		if joint and joint:IsA("Motor6D") and joint:GetAttribute("RestC0") then
			joint.C0 = joint:GetAttribute("RestC0")
		elseif joint and joint:IsA("AnimationConstraint") and joint.Attachment0 and joint.Attachment0:GetAttribute("RestCFrame") then
			joint.Attachment0.CFrame = joint.Attachment0:GetAttribute("RestCFrame")
		end
	end
end
local function clearHeld(player: Player)
	local char = player.Character
	local old = char and char:FindFirstChild("HeldFish")
	if old then
		old:Destroy()
	end
	setArmsUp(char, false)
end

local FishModels = Shared:FindFirstChild("FishModels")

local function showHeld(player: Player)
	clearHeld(player)
	local id = player:GetAttribute("Holding")
	local char = player.Character
	local f = id and Config.BY_ID[id]
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")) :: BasePart?
	if not f or not hand then
		return
	end
	local sizeIndex = player:GetAttribute("HoldingSize") or 3
	local s = Config.SIZES[sizeIndex]
	-- rarer fish are held up bigger (Epic, the top rarity, is about three times a player's height)
	local w = 3.2 * s.scale * (FishAura.HOLD_SCALE[f.rarity] or 1)
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(240, 40)
	tag.MaxDistance = 60
	tag.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Michroma
	label.TextScaled = true
	label.TextColor3 = Config.RARITY[f.rarity].color
	label.Text = ("%s %s  ·  %s"):format(string.upper(s.name), string.upper(f.name), string.upper(f.rarity))
	label.TextStrokeTransparency = 0.3
	label.Parent = tag
	local light = Instance.new("PointLight")
	light.Color = Config.RARITY[f.rarity].color
	light.Range = 8
	light.Brightness = 1.5

	local src = FishModels and FishModels:FindFirstChild(id)
	if src then
		-- the 3D fish model, sized to the catch, held out sideways in the right hand
		local m = src:Clone()
		local len = m:GetAttribute("Length") or 2
		m:ScaleTo(m:GetScale() * w / len)
		local _, ext = m:GetBoundingBox()
		-- held up over the head with both arms, side-on, head toward the character's right (showing off the catch)
		local torso = char:FindFirstChild("Head") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or hand
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local facing = if root then root.CFrame.Rotation else torso.CFrame.Rotation
		local headTop = torso.Position.Y + torso.Size.Y / 2
		m:PivotTo(CFrame.new(torso.Position.X, headTop + 0.35 + ext.Y / 2, torso.Position.Z) * facing * CFrame.new(0, 0, -0.2) * CFrame.Angles(0, math.rad(-90), 0))
		setArmsUp(char, true)
		local biggest
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = torso
				weld.Part1 = p
				weld.Parent = p
				p.Anchored = false
				p.Massless = true
				p.CanCollide = false
				if not biggest or p.Size.Magnitude > biggest.Size.Magnitude then
					biggest = p
				end
			end
		end
		m.Name = "HeldFish"
		if biggest then
			tag.StudsOffsetWorldSpace = Vector3.new(0, ext.Y / 2 + 1, 0)
			tag.Adornee = biggest
			tag.Parent = biggest
			light.Parent = biggest
		end
		FishAura.apply(m, f.rarity) -- rarity aura: stronger the rarer the fish
		m.Parent = char
		return
	end

	-- fallback: the flat fish card
	local part = Instance.new("Part")
	part.Name = "HeldFish"
	part.Size = Vector3.new(w, w / 2, 0.05)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.LightInfluence = 0
		sg.Brightness = 1.6
		sg.CanvasSize = Vector2.new(512, 256)
		sg.Parent = part
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = Art.fish[f.id]
		if face == Enum.NormalId.Back then
			img.ImageRectOffset = Vector2.new(512, 0)
			img.ImageRectSize = Vector2.new(-512, 256)
		end
		img.Parent = sg
	end
	light.Parent = part
	tag.StudsOffsetWorldSpace = Vector3.new(0, w / 2 + 1, 0)
	tag.Parent = part
	local weld = Instance.new("Weld")
	local head = char:FindFirstChild("Head") :: BasePart?
	weld.Part0 = head or hand
	weld.Part1 = part
	weld.C0 = if head then CFrame.new(0, head.Size.Y / 2 + 0.35 + w / 4, -0.2) * CFrame.Angles(0, math.rad(90), 0) else CFrame.new(0, -hand.Size.Y / 2 - w / 4, -0.4) * CFrame.Angles(0, math.rad(90), 0)
	setArmsUp(char, true)
	weld.Parent = part
	part.Parent = char
end

CatalogRF.OnServerInvoke = function(player: Player, req)
	local p = Profiles.get(player)
	if not p or typeof(req) ~= "table" then
		return nil
	end
	if req.action == "hold" then
		local e = p.catalog[req.id]
		if not e then
			return { ok = false, message = "Catch it first!" }
		end
		if player:GetAttribute("Holding") == req.id then
			player:SetAttribute("Holding", nil)
			clearHeld(player)
			return { ok = true, holding = nil }
		end
		player:SetAttribute("Holding", req.id)
		player:SetAttribute("HoldingSize", e.best)
		showHeld(player)
		return { ok = true, holding = req.id }
	elseif req.action == "stow" then
		player:SetAttribute("Holding", nil)
		clearHeld(player)
		return { ok = true }
	end
	return { ok = true, catalog = p.catalog }
end

---------------------------------------------------------------- daily streak

local function checkStreak(player: Player, p)
	local day = Profiles.today()
	if p.streak.day == day then
		return
	end
	local count = if p.streak.day == day - 1 then p.streak.count + 1 else 1
	p.streak = { day = day, count = count }
	local slot = ((count - 1) % #Config.STREAK) + 1
	local coins = math.floor(Config.STREAK[slot] * tierMult(p))
	Profiles.addCoins(player, coins)
	local luck = slot == #Config.STREAK
	if luck then
		p.luckUntil = math.max(p.luckUntil, os.time()) + Config.LUCK_BOOST_SECONDS
	end
	Profiles.markDirty(player)
	State:FireClient(player, { type = "streak", count = count, slot = slot, coins = coins, luck = luck, rewards = Config.STREAK })
end

---------------------------------------------------------------- passes and products

local function applyPasses(player: Player)
	for key, id in Config.PASSES do
		if id ~= 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
			if ok and owns then
				player:SetAttribute("Pass_" .. key, true)
			end
		end
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
	if not bought then
		return
	end
	Funnels.step(player, "RobuxShop", 3) -- Purchase Completed (game pass)
	for key, id in Config.PASSES do
		if id == passId then
			player:SetAttribute("Pass_" .. key, true)
			push(player)
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(30)
		for _, plr in Players:GetPlayers() do
			local pp = Profiles.get(plr)
			if pp then
				local before = pp.playSeconds or 0
				pp.playSeconds = before + 30
				if before < Config.STARTER.seconds then
					Profiles.markDirty(plr) -- only matters for the first hour
				end
				-- the Starter Pack offer just ran out: tell the client so the shop hides it
				if not pp.starterBought and before < Config.STARTER.seconds and pp.playSeconds >= Config.STARTER.seconds then
					push(plr)
				end
			end
		end
	end
end)

local granted = {}
MarketplaceService.ProcessReceipt = function(info)
	if granted[info.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local p = player and Profiles.get(player)
	if not p then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local pid = info.ProductId
	if pid == Config.PRODUCTS.STARTER_PACK and pid ~= 0 then
		-- Starter Pack: a Rare Boost, a medium coin pack and the Starter line color
		p.luckUntil = math.max(p.luckUntil, os.time()) + Config.LUCK_BOOST_SECONDS
		Profiles.addCoins(player, Config.coinPack("COINS_MEDIUM", p.upgrades))
		p.starterBought = true
		p.starterLine = true
	elseif pid == Config.PRODUCTS.LUCKY_LURE and pid ~= 0 then
		p.luckUntil = math.max(p.luckUntil, os.time()) + Config.LUCK_BOOST_SECONDS
	elseif pid == Config.PRODUCTS.SERVER_LUCK and pid ~= 0 then
		serverLuckUntil = math.max(serverLuckUntil, os.time()) + Config.LUCK_BOOST_SECONDS
		for _, other in Players:GetPlayers() do
			State:FireClient(other, { type = "serverLuck", who = player.DisplayName, untilTime = serverLuckUntil })
			push(other)
		end
	else
		local found = false
		for key, coins in Config.COIN_PACKS do
			if Config.PRODUCTS[key] == pid and pid ~= 0 then
				Profiles.addCoins(player, Config.coinPack(key, p.upgrades)) -- grows with your progress
				_ = coins
				found = true
			end
		end
		if not found then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	granted[info.PurchaseId] = true
	Funnels.step(player, "RobuxShop", 3) -- Purchase Completed (developer product)
	rebirthCheck(player, p)
	Profiles.markDirty(player)
	task.spawn(Profiles.save, player)
	push(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------- world prompts (merchant, terminals, gate)

local function prompt(model: Instance?, action: string, object: string, kind: string)
	if not model then
		return
	end
	local part = model:IsA("BasePart") and model or model:FindFirstChildWhichIsA("BasePart", true)
	if not part then
		return
	end
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	if model == merchant then
		pp.MaxActivationDistance = 18 -- the cat stands behind the counter
	end
	pp.Parent = part
	pp.Triggered:Connect(function(player)
		if kind == "sell" then
			local r = sellAll(player)
			State:FireClient(player, { type = "sold", result = r })
		elseif kind == "sellshop" then
			-- one button at the cat: sell whatever is in your bucket, then open the shop
			local p = Profiles.get(player)
			if p and #p.cargo > 0 then
				local r = sellAll(player)
				State:FireClient(player, { type = "sold", result = r })
			end
			if p then
				Funnels.start(player, "Upgrades", nil, field("Area - " .. AREA_NAMES[Config.tierOf(p.upgrades)]))
			end
			State:FireClient(player, { type = "open", menu = "shop" })
		else
			if kind == "shop" then
				-- the Upgrades window (Captain Whiskers or the upgrade terminal): a new Upgrades funnel attempt
				local p = Profiles.get(player)
				if p then
					Funnels.start(player, "Upgrades", nil, field("Area - " .. AREA_NAMES[Config.tierOf(p.upgrades)]))
				end
			end
			State:FireClient(player, { type = "open", menu = kind })
		end
	end)
end
prompt(merchant, "Shop", "Captain Whiskers", "shop")

-- Fish quests from the cat: he asks for 1 to 3 of a fish you have already caught. Catch them,
-- then talk to him again to collect. He only gives quests once you've caught a few kinds of fish.
local function uniqueCaught(p): number
	local n = 0
	for id in p.catalog do
		if Config.BY_ID[id] then
			n += 1
		end
	end
	return n
end

local function pickQuest(p)
	local options = {}
	for id in p.catalog do
		if Config.BY_ID[id] then
			table.insert(options, id)
		end
	end
	local id = options[math.random(1, #options)]
	local need = math.random(1, Config.CAT_QUEST.maxCount)
	local reward = Config.CAT_QUEST.perUnique * uniqueCaught(p) + need * need * Config.CAT_QUEST.valueMult * Config.BY_ID[id].value
	return { id = id, need = need, have = 0, reward = math.floor(reward), sid = HttpService:GenerateGUID(false) }
end

local talking: { [Player]: boolean } = {}
-- Zorp talks in the talk box (FishClient.Dialog): lines type out with his babble voice
local function catSay(player: Player, text: string | { string }, _good: boolean?)
	State:FireClient(player, { type = "talk", who = "Zorp", lines = if typeof(text) == "table" then text else { text } })
end

local function catQuest(player: Player)
	local p = Profiles.get(player)
	if not p or talking[player] then
		return
	end
	local q = p.fishQuest
	if q and q.have >= q.need then
		Profiles.addCoins(player, q.reward)
		p.fishQuest = nil
		questSession(player, q)
		Funnels.step(player, "ZorpQuest", 3) -- Quest Turned In
		Funnels.finish(player, "ZorpQuest")
		rebirthCheck(player, p)
		Profiles.markDirty(player)
		push(player)
		catSay(player, { "You found them! Thank you, thank you!", ("Here's your reward: %d coins!"):format(q.reward) })
	elseif q then
		local f = Config.BY_ID[q.id]
		catSay(player, ("Still looking for %d %s... you've got %d so far. Good luck out there!"):format(q.need, f.name, q.have), false)
	elseif uniqueCaught(p) < Config.CAT_QUEST.minUnique then
		catSay(player, { "Oh! You're new around here, huh?", ("Catch %d different kinds of fish, then come see me. You've got %d so far!"):format(Config.CAT_QUEST.minUnique, uniqueCaught(p)) }, false)
	else
		talking[player] = true
		local nq = pickQuest(p)
		local f = Config.BY_ID[nq.id]
		-- the whole speech goes to the talk box at once, and the quest is given right away: the client shows its
		-- card the moment Zorp finishes talking (it used to wait out a fixed delay here, so the card came late)
		local lines = { "Hey you!", "Do you have a moment?", ("Lately everyone wants to buy %s..."):format(f.name), ("Could you bring me %d?"):format(nq.need) }
		catSay(player, lines)
		p.fishQuest = nq
		p.questsUnlocked = true
		Profiles.markDirty(player)
		push(player)
		State:FireClient(player, { type = "newQuest", id = nq.id, need = nq.need, reward = nq.reward })
		Funnels.start(player, "ZorpQuest", nq.sid, field("Rarity - " .. f.rarity)) -- Quest Accepted
		task.delay(1.5, function()
			talking[player] = nil -- (a moment's pause so a double press doesn't restart his speech)
		end)
	end
end

-- the cat chats to whoever walks by
do
	local speech = merchant and merchant:FindFirstChild("Speech", true)
	local label = speech and speech:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		task.spawn(function()
			while true do
				label.Text = Config.CAT_LINES[math.random(1, #Config.CAT_LINES)]
				task.wait(math.random(7, 15))
			end
		end)
	end
end
do
	-- quests come from Zorp, the little green alien (one by the shop and one at each dock)
	for _, alien in World:GetDescendants() do
		if alien.Name == "QuestAlien" and alien:IsA("Model") then
			local part = alien:FindFirstChild("Platform") or alien:FindFirstChildWhichIsA("BasePart", true)
			if part then
				-- one button for Zorp: he buys the fish in your bucket and handles your quest
				local zp = Instance.new("ProximityPrompt")
				zp.Name = "ZorpPrompt"
				zp.ActionText = "Sell & Quest"
				zp.ObjectText = "Zorp"
				zp.HoldDuration = 0
				zp.MaxActivationDistance = 12
				zp.RequiresLineOfSight = false
				zp.Parent = part
				zp.Triggered:Connect(function(player)
					local p = Profiles.get(player)
					if p and #p.cargo > 0 then
						local r = sellAll(player)
						if r.ok then
							catSay(player, { "Ooh, fresh fish!", ("That's %d fish for %d coins. Pleasure doing business!"):format(r.count, r.coins) })
						else
							State:FireClient(player, { type = "sold", result = r })
						end
					end
					catQuest(player)
				end)
			end
		end
	end
end
prompt(World:FindFirstChild("UpgradeTerminal", true), "Upgrades", "Upgrade Terminal", "shop")
prompt(World:FindFirstChild("CatalogTerminal", true), "Open", "Cosmic Catalog", "catalog")
prompt(World:FindFirstChild("QuestBoard", true), "Quests", "Quest Board", "quests")
prompt(World:FindFirstChild("World2Gate", true), "Plan expedition", "Expedition Terminal", "world2")
-- (the shop terminal has no prompt of its own: talk to the cat for the shop; sell to Zorp)

-- the floating game-pass displays in the plaza (Auto Fish, Auto Sell, 2x Coins, God Fishing Rod)
do
	-- every model with a PassKey attribute sells that pass: the floating stands and the shop holograms
	do
		for _, m in World:GetDescendants() do
			local key = m:IsA("Model") and m:GetAttribute("PassKey")
			local pp = key and m:FindFirstChild("BuyPrompt", true)
			if key and pp then
				pp.Triggered:Connect(function(player)
					local id = Config.PASSES[key] or 0
					local label = pp.ObjectText
					if hasPass(player, key) then
						State:FireClient(player, { type = "sold", result = { ok = true, message = "You already own " .. label .. "!" } })
					elseif id ~= 0 then
						Funnels.start(player, "RobuxShop", nil, field("Source - Lobby Stand"))
						Funnels.step(player, "RobuxShop", 2) -- Purchase Prompt Shown
						MarketplaceService:PromptGamePassPurchase(player, id)
					else
						State:FireClient(player, { type = "sold", result = { ok = false, message = label .. " is coming soon!" } })
					end
				end)
			end
			-- stands that sell a developer product (Server Rare Boost) have a ProductKey instead
			local pkey = m:IsA("Model") and m:GetAttribute("ProductKey")
			local ppp = pkey and m:FindFirstChild("BuyPrompt", true)
			if pkey and ppp then
				ppp.Triggered:Connect(function(player)
					local id = Config.PRODUCTS[pkey] or 0
					if id ~= 0 then
						Funnels.start(player, "RobuxShop", nil, field("Source - Lobby Stand"))
						Funnels.step(player, "RobuxShop", 2) -- Purchase Prompt Shown
						MarketplaceService:PromptProductPurchase(player, id)
					else
						State:FireClient(player, { type = "sold", result = { ok = false, message = ppp.ObjectText .. " is coming soon!" } })
					end
				end)
			end
		end
	end
end

---------------------------------------------------------------- Studio testing: give yourself a fish
-- Only exists in Studio play tests (never in the live game). From the command bar / server:
--   game.ServerStorage.DevGiveFish:Invoke(player, "event_horizon_eel", 5)   -- id, size index (5 = Huge)
if game:GetService("RunService"):IsStudio() then
	local give = Instance.new("BindableFunction")
	give.Name = "DevGiveFish"
	give.OnInvoke = function(player: Player, id: string, size: number?)
		local p = Profiles.get(player)
		local f = Config.BY_ID[id]
		if not p or not f then
			return false
		end
		local entry = { id = id, size = math.clamp(size or #Config.SIZES, 1, #Config.SIZES) }
		table.insert(p.cargo, { id = entry.id, size = entry.size })
		addToCatalog(player, p, entry)
		p.stats.caught += 1
		if Config.RARITY[f.rarity].order >= 3 then
			p.stats.rare = (p.stats.rare or 0) + 1
		end
		p.stats.biggest = math.max(p.stats.biggest, fishValue(player, entry))
		-- hold it up so you can see it
		player:SetAttribute("Holding", id)
		player:SetAttribute("HoldingSize", p.catalog[id].best)
		showHeld(player)
		push(player)
		return true
	end
	give.Parent = game:GetService("ServerStorage")

	-- game.ServerStorage.DevMaxUpgrades:Invoke(player)   -- every upgrade to its top level
	local maxUp = Instance.new("BindableFunction")
	maxUp.Name = "DevMaxUpgrades"
	maxUp.OnInvoke = function(player: Player)
		local p = Profiles.get(player)
		if not p then
			return false
		end
		for key, u in Config.UPGRADES do
			p.upgrades[key] = #u.costs
		end
		Profiles.markDirty(player)
		push(player)
		return true
	end
	maxUp.Parent = game:GetService("ServerStorage")

	-- game.ServerStorage.DevGiveCoins:Invoke(player, 5000)
	local coins = Instance.new("BindableFunction")
	coins.Name = "DevGiveCoins"
	coins.OnInvoke = function(player: Player, n: number)
		local c = Profiles.addCoins(player, n or 1000)
		push(player)
		return c
	end
	coins.Parent = game:GetService("ServerStorage")

	-- game.ServerStorage.DevTalkZorp:Invoke(player)   -- same as talking to Zorp (get / turn in a fish quest)
	local talk = Instance.new("BindableFunction")
	talk.Name = "DevTalkZorp"
	talk.OnInvoke = function(player: Player)
		catQuest(player)
		return true
	end
	talk.Parent = game:GetService("ServerStorage")

	-- game.ServerStorage.DevRareBoost:Invoke(player)   -- 15 minutes of Rare Boost (as if bought)
	local boostDev = Instance.new("BindableFunction")
	boostDev.Name = "DevRareBoost"
	boostDev.OnInvoke = function(player: Player)
		local p = Profiles.get(player)
		if not p then
			return false
		end
		p.luckUntil = math.max(p.luckUntil, os.time()) + Config.LUCK_BOOST_SECONDS
		push(player)
		return true
	end
	boostDev.Parent = game:GetService("ServerStorage")
end

---------------------------------------------------------------- players

local function onCharacter(player: Player)
	task.wait(0.5)
	if player:GetAttribute("Holding") then
		showHeld(player)
	end
end

-- the Join the Group sign shows the welcome gift from Config
do
	local sign = workspace:FindFirstChild("World") and workspace.World.Lobby:FindFirstChild("JoinGroupSign")
	local lbl = sign and sign:FindFirstChild("GiftLabel", true)
	if lbl and Config.GROUP then
		lbl.Text = ("GET %d COINS"):format(Config.GROUP.joinGift)
	end
end

-- the Robux Shop window and its buy buttons live on the client: it tells the server, which checks and logs.
-- Only two known signals are accepted, from a fixed list of sources, at most once a second each.
do
	local signal = Remotes:FindFirstChild("AnalyticsSignal") or Instance.new("RemoteEvent")
	signal.Name = "AnalyticsSignal"
	signal.Parent = Remotes
	local SOURCES = { ["Side Button"] = true, ["Coin Plus"] = true }
	local last: { [Player]: { [string]: number } } = {}
	signal.OnServerEvent:Connect(function(player, kind, source)
		if typeof(kind) ~= "string" then
			return
		end
		local now = os.clock()
		last[player] = last[player] or {}
		if (last[player][kind] or -math.huge) > now - 1 then
			return
		end
		last[player][kind] = now
		if kind == "shopOpened" and typeof(source) == "string" and SOURCES[source] then
			Funnels.start(player, "RobuxShop", nil, field("Source - " .. source)) -- Opened Shop
		elseif kind == "promptShown" then
			Funnels.step(player, "RobuxShop", 2) -- Purchase Prompt Shown
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
	end)
end

Players.PlayerAdded:Connect(function(player)
	local p = Profiles.load(player)
	Onboarding.begin(player, not p.tutorialDone) -- only first-time players enter the new-player funnel
	applyPasses(player)
	task.spawn(checkGroup, player)
	player:SetAttribute("Coins", p.coins)
	player:SetAttribute("TotalCaught", p.stats.caught)
	player:SetAttribute("Earned", p.earned)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	ls.Parent = player
	local fishStat = Instance.new("IntValue")
	fishStat.Name = "Fish"
	fishStat.Value = p.stats.caught
	fishStat.Parent = ls
	player:GetAttributeChangedSignal("TotalCaught"):Connect(function()
		fishStat.Value = player:GetAttribute("TotalCaught") or 0
	end)
	local rbStat = Instance.new("IntValue")
	rbStat.Name = "Rebirths"
	rbStat.Value = p.rebirths
	rbStat.Parent = ls
	player:SetAttribute("Rebirths", p.rebirths)
	-- a star and the count in front of your name over your head (e.g. "★3 Name")
	local function nameTag()
		local n = player:GetAttribute("Rebirths") or 0
		rbStat.Value = n
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayName = if n > 0 then ("★%d %s"):format(n, player.DisplayName) else player.DisplayName
		end
	end
	player:GetAttributeChangedSignal("Rebirths"):Connect(nameTag)
	player.CharacterAdded:Connect(function(ch)
		ch:WaitForChild("Humanoid", 5)
		nameTag()
	end)
	nameTag()
	ensureQuests(p)
	rebirthCheck(player, p)
	awardEarned(player, p)
	player.CharacterAdded:Connect(function()
		onCharacter(player)
	end)
	push(player)
	task.delay(2, function()
		if player.Parent then
			checkStreak(player, p)
			push(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	casts[player] = nil
	talking[player] = nil
	seas[player] = nil
	Profiles.unload(player)
end)
