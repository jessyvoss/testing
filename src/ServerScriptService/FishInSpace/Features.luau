-- Fish in Space: server side of the Nov 2026 features (numbers in Config, under FEATURES).
--   Meteor Shower event and private-server host controls, promo codes, holiday fish and the secret fish,
--   crafting, surprise pearls, the Quest Master streak, the deep-space trap, the Abyss bonus, the fishing crew
--   bonus, and the moment-of-need products (keep a lost fish, double a sale, bucket space, streak restore,
--   the Luck Upgrade ladder and rewarded video ads).
-- Main.server.luau calls in here at a few points (search Main for "Features.").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage.FishInSpace
local Config = require(Shared.Config)

local Features = {}
local ctx -- set by Features.init: { Profiles, State, push, hasPass, fishValue, cargoCap, tierMult, addToCatalog, casts, track }

local function say(player: Player, text: string, color: string?)
	ctx.State:FireClient(player, { type = "feature", kind = "toast", text = text, color = color })
end

local function today(): number
	return math.floor(os.time() / 86400)
end

---------------------------------------------------------------- special fish (holiday + secret)

-- their models are tinted copies of the fish they're based on (pictures: Art.luau points them at the base picture)
local function makeSpecialModels()
	local models = Shared:FindFirstChild("FishModels")
	if not models then
		return
	end
	for _, f in Config.SPECIAL_FISH do
		local src = models:FindFirstChild(f.base)
		if src and not models:FindFirstChild(f.id) then
			local m = src:Clone()
			m.Name = f.id
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.Color = d.Color:Lerp(f.tint, 0.7)
					if d:IsA("MeshPart") then
						d.TextureID = "" -- (so the tint shows)
					end
				end
			end
			m.Parent = models
		end
	end
end

-- newEntry rolls a normal fish first; this may swap it for a holiday fish or the secret fish
function Features.swapSpecial(rng, li: number, f, p)
	local s = Config.SECRET_FISH
	if p and p.secret and li == s.layer and rng:NextNumber() < s.chance then
		return s
	end
	for _, h in Config.HOLIDAY_FISH do
		if h.layer == li and Config.holidayOpen(h) and rng:NextNumber() < h.chance then
			return h
		end
	end
	return f
end

---------------------------------------------------------------- meteor shower

local meteorUntil = 0
local hostLast = 0

function Features.meteorActive(): boolean
	return os.time() < meteorUntil
end

local function startMeteor()
	meteorUntil = os.time() + Config.METEOR.duration
	workspace:SetAttribute("MeteorUntil", meteorUntil)
	ctx.State:FireAllClients({ type = "feature", kind = "meteor", untilTime = meteorUntil })
	for _, plr in Players:GetPlayers() do
		ctx.push(plr) -- (the boost countdown on the HUD)
	end
end

local function meteorLoop()
	local nextAt = os.time() + Config.METEOR.firstDelay
	while true do
		workspace:SetAttribute("MeteorNext", nextAt)
		local warnAt = nextAt - Config.METEOR.warn
		while os.time() < warnAt do
			task.wait(1)
			local n = workspace:GetAttribute("MeteorNext")
			if n ~= nextAt then -- a host started one early: the schedule moved
				nextAt = n
				warnAt = nextAt - Config.METEOR.warn
			end
		end
		ctx.State:FireAllClients({ type = "feature", kind = "meteorSoon", at = nextAt })
		while os.time() < nextAt do
			task.wait(1)
		end
		startMeteor()
		task.wait(Config.METEOR.duration)
		for _, plr in Players:GetPlayers() do
			ctx.push(plr)
		end
		nextAt = os.time() + Config.METEOR.every
	end
end

---------------------------------------------------------------- catches: crew, abyss, pearls, secret

local fishingAt: { [Player]: { pier: string, t: number } } = {}

function Features.onCastStart(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pier = root and Config.fishPier(root.Position, 2)
	fishingAt[player] = if pier then { pier = pier.name, t = os.clock() } else nil
end

-- extra % on a catch: other players fishing at your dock, and the Abyss
function Features.catchBonus(player: Player, entry): number
	local pct = 0
	local me = fishingAt[player]
	if me then
		local crew = 0
		for other, at in fishingAt do
			if other ~= player and other.Parent and at.pier == me.pier and os.clock() - at.t < 90 then
				crew += 1
			end
		end
		pct += math.min(Config.CREW.max, crew * Config.CREW.bonusPct)
	end
	if (entry.depth or 0) >= Config.ABYSS.from then
		pct += Config.ABYSS.bonusPct
	end
	return pct
end

function Features.onCatch(player: Player, p, item, value: number)
	-- a pearl inside (a surprise)
	if math.random() < Config.SURPRISE.chance then
		local coins = math.floor(value * Config.SURPRISE.mult)
		ctx.Profiles.addCoins(player, coins)
		ctx.State:FireClient(player, { type = "feature", kind = "pearl", coins = coins, id = item.id })
	end
	-- all four kinds of junk: the signal in The Void
	local f = Config.BY_ID[item.id]
	if f and f.rarity == "Junk" and not p.secret then
		local all = true
		for _, j in Config.JUNK do
			if not p.catalog[j.id] then
				all = false
			end
		end
		if all then
			p.secret = true
			ctx.State:FireClient(player, { type = "feature", kind = "secret" })
		end
	end
end

---------------------------------------------------------------- quest master

function Features.onQuestClaimed(player: Player, p)
	local list = p.quests and p.quests.daily
	if typeof(list) ~= "table" then
		return
	end
	for _, q in list do
		if not q.claimed then
			return
		end
	end
	local qs = p.questStreak
	local d = today()
	if qs.day == d then
		return
	end
	qs.count = if qs.day == d - 1 then qs.count + 1 else 1
	qs.day = d
	if qs.count >= Config.QUEST_STREAK.days and not p.questMaster then
		p.questMaster = true
		ctx.State:FireClient(player, { type = "feature", kind = "questMaster" })
	else
		say(player, ("All quests done! Quest streak: %d / %d days"):format(math.min(qs.count, Config.QUEST_STREAK.days), Config.QUEST_STREAK.days), "green")
	end
end

---------------------------------------------------------------- daily streak restore

-- called by the daily streak check: remember a streak that just broke so it can be restored today
function Features.onStreak(p, prevCount: number, newCount: number)
	if newCount == 1 and prevCount >= 2 then
		p.lostStreak = { count = prevCount, day = today() }
	elseif p.lostStreak and p.lostStreak.day ~= today() then
		p.lostStreak = nil
	end
end

---------------------------------------------------------------- products

local pendingKeep: { [Player]: { id: string, size: number, depth: number, t: number } } = {}
local lastSale: { [Player]: { total: number, t: number } } = {}

function Features.onSell(player: Player, total: number)
	lastSale[player] = { total = total, t = os.clock() }
	if Config.PRODUCTS.DOUBLE_SALE ~= 0 and total >= 50 then
		ctx.State:FireClient(player, { type = "feature", kind = "sold", total = total })
	end
end

local function productKey(pid: number): string?
	if pid == 0 then
		return nil
	end
	for key, id in Config.PRODUCTS do
		if id == pid then
			return key
		end
	end
	return nil
end

-- returns true when this receipt was one of ours (and has been applied to the profile)
function Features.grantProduct(player: Player, p, pid: number): boolean
	local key = productKey(pid)
	if not key then
		return false
	end
	if key == "KEEP_FISH" then
		local k = pendingKeep[player]
		pendingKeep[player] = nil
		if k and os.clock() - k.t < 120 then
			local item = { id = k.id, size = k.size, bonus = math.floor(Config.depthBonus(k.id, k.depth)) }
			table.insert(p.cargo, item) -- (even if your bucket is full)
			ctx.addToCatalog(player, p, { id = k.id, size = k.size })
			p.stats.caught += 1
			ctx.State:FireClient(player, { type = "feature", kind = "kept", caught = { { id = k.id, size = k.size, value = ctx.fishValue(player, item) } } })
		else
			-- (the offer had run out by the time the purchase finished: a Rare Boost instead, so it's never wasted)
			p.luckUntil = math.max(p.luckUntil, os.time()) + 10 * 60
			say(player, "The fish was gone, so Zorp gave you a 10 minute Rare Boost instead!", "green")
		end
	elseif key == "DOUBLE_SALE" then
		local s = lastSale[player]
		lastSale[player] = nil
		local coins = if s then s.total else math.floor(Config.COIN_PACKS.COINS_SMALL * ctx.tierMult(p))
		ctx.Profiles.addCoins(player, coins)
		p.earned += coins
		say(player, ("Sale doubled! +%d coins"):format(coins), "green")
	elseif key == "BUCKET_PLUS" then
		player:SetAttribute("BucketPlus", (player:GetAttribute("BucketPlus") or 0) + Config.BUCKET_PLUS)
		say(player, ("+%d bucket slots until you leave this server"):format(Config.BUCKET_PLUS), "green")
	elseif key == "STREAK_RESTORE" then
		local ls = p.lostStreak
		if ls then
			p.streak.count = ls.count + 1
			p.lostStreak = nil
			say(player, ("Streak restored: day %d!"):format(p.streak.count), "green")
		else
			p.luckUntil = math.max(p.luckUntil, os.time()) + 10 * 60
			say(player, "Your streak was fine, so here's a 10 minute Rare Boost instead!", "green")
		end
	elseif key:match("^LUCK_%d$") then
		local n = tonumber(key:sub(6))
		if n and p.luckLadder < n then
			p.luckLadder = math.min(Config.LUCK_LADDER.max, n)
		end
		say(player, ("Luck Upgrade %d! Your area's rarest fish show up more often"):format(p.luckLadder), "green")
	elseif key == "AD_BAIT" then
		p.luckUntil = math.max(p.luckUntil, os.time()) + Config.LUCK_BOOST_AD * 60
		say(player, ("Thanks for watching! %d minutes of Rare Boost"):format(Config.LUCK_BOOST_AD), "green")
	else
		return false
	end
	return true
end

---------------------------------------------------------------- requests from the client

-- the fish that got away (the client says which pool fish; the server checks it was in this cast)
function Features.fishAction(player: Player, p, req)
	if req.action == "lost" then
		local c = ctx.casts[player]
		local i = tonumber(req.index)
		local entry = c and i and c.pool[i]
		if not entry then
			return { ok = false }
		end
		local f = Config.BY_ID[entry.id]
		if not f or Config.RARITY[f.rarity].order < 3 then
			return { ok = false }
		end
		pendingKeep[player] = { id = entry.id, size = entry.size, depth = entry.depth, t = os.clock() }
		return { ok = true, offer = Config.PRODUCTS.KEEP_FISH ~= 0 }
	end
	return nil
end

local AdService = game:GetService("AdService")

function Features.shopAction(player: Player, p, req)
	local action = req.action
	if action == "code" then
		local code = typeof(req.code) == "string" and string.upper(req.code):gsub("%s", "") or ""
		local c = Config.CODES[code]
		if not c then
			return { ok = false, message = "That code doesn't work" }
		end
		if p.codes[code] then
			return { ok = false, message = "You already used that code" }
		end
		p.codes[code] = true
		local coins = math.floor((c.coins or 0) * ctx.tierMult(p))
		if coins > 0 then
			ctx.Profiles.addCoins(player, coins)
		end
		if (c.boostMin or 0) > 0 then
			p.luckUntil = math.max(p.luckUntil, os.time()) + c.boostMin * 60
		end
		return { ok = true, message = ("Code redeemed! +%d coins%s"):format(coins, if (c.boostMin or 0) > 0 then (" and %d min Rare Boost"):format(c.boostMin) else "") }
	elseif action == "craft" then
		local r
		for _, rr in Config.RECIPES do
			if rr.id == req.id then
				r = rr
			end
		end
		if not r then
			return { ok = false, message = "Unknown recipe" }
		end
		-- find the fish in your bucket (the least valuable ones of each kind first)
		local use = {}
		for id, n in r.needs do
			local idx = {}
			for i, c in p.cargo do
				if c.id == id then
					table.insert(idx, i)
				end
			end
			if #idx < n then
				return { ok = false, message = ("You need %d %s in your bucket"):format(n, Config.BY_ID[id].name) }
			end
			table.sort(idx, function(a, b)
				return ctx.fishValue(player, p.cargo[a]) < ctx.fishValue(player, p.cargo[b])
			end)
			for k = 1, n do
				table.insert(use, idx[k])
			end
		end
		local worth = 0
		for _, i in use do
			worth += ctx.fishValue(player, p.cargo[i])
		end
		table.sort(use, function(a, b)
			return a > b
		end)
		for _, i in use do
			table.remove(p.cargo, i)
		end
		local rw = r.reward
		local got = {}
		if rw.boostMin then
			p.luckUntil = math.max(p.luckUntil, os.time()) + rw.boostMin * 60
			table.insert(got, rw.boostMin .. " min Rare Boost")
		end
		if rw.coinsMult then
			local coins = math.floor(worth * rw.coinsMult)
			ctx.Profiles.addCoins(player, coins)
			p.earned += coins
			table.insert(got, coins .. " coins")
		end
		if rw.coins then
			local coins = math.floor(rw.coins * ctx.tierMult(p))
			ctx.Profiles.addCoins(player, coins)
			table.insert(got, coins .. " coins")
		end
		if rw.line then
			p.lines[rw.line] = true
			table.insert(got, "a new fishing line")
		end
		return { ok = true, message = r.name .. "! " .. table.concat(got, ", ") }
	elseif action == "trap" then
		local now = os.time()
		if not p.trap then
			p.trap = { t = now }
			return { ok = true, message = "Trap set! Come back later to collect what it catches", trap = p.trap }
		end
		local n = math.min(math.floor((now - p.trap.t) / Config.TRAP.perFish), Config.TRAP.maxFish)
		local space = ctx.cargoCap(player, p) - #p.cargo
		if n <= 0 then
			local left = Config.TRAP.perFish - (now - p.trap.t)
			return { ok = false, message = ("Nothing yet. The first fish comes in %d min"):format(math.ceil(left / 60)) }
		end
		if space <= 0 then
			return { ok = false, message = "Your bucket is full. Sell first, then collect the trap" }
		end
		n = math.min(n, space)
		-- fish from the deepest area you can fish, only kinds your bait can catch
		local li = Config.tierOf(p.upgrades)
		local bait = if ctx.hasPass(player, "GOD_ROD") then 4 else Config.baitMax(p.upgrades.lure)
		local w = Config.layerWeights(li, false, (p.perks.lucky or 0) + 0.5 * p.luckLadder)
		local pool, total = {}, 0
		for rarity, wt in w do
			if Config.RARITY[rarity].order <= bait then
				pool[rarity] = wt
				total += wt
			end
		end
		local caught = {}
		for _ = 1, n do
			local r = math.random() * total
			local rarity = "Common"
			for k, wt in pool do
				r -= wt
				if r <= 0 then
					rarity = k
					break
				end
			end
			local list = {}
			for _, f in (if rarity == "Junk" then Config.JUNK else Config.FISH) do
				if f.rarity == rarity then
					table.insert(list, f)
				end
			end
			local f = list[math.random(1, #list)]
			local size = math.random(1, 4) -- (trap fish are never Huge)
			local item = { id = f.id, size = size, bonus = 0 }
			table.insert(p.cargo, item)
			local isNew = ctx.addToCatalog(player, p, { id = f.id, size = size })
			p.stats.caught += 1
			ctx.track(player, "catch", 1)
			table.insert(caught, { id = f.id, size = size, value = ctx.fishValue(player, item), new = isNew })
		end
		p.trap = nil
		return { ok = true, message = ("Your trap caught %d fish!"):format(n), caught = caught }
	elseif action == "hostMeteor" then
		if game.PrivateServerOwnerId == 0 or game.PrivateServerOwnerId ~= player.UserId then
			return { ok = false, message = "Only the private server's owner can do that" }
		end
		if os.clock() - hostLast < Config.METEOR.hostCooldown and hostLast > 0 then
			return { ok = false, message = ("Ready again in %d min"):format(math.ceil((Config.METEOR.hostCooldown - (os.clock() - hostLast)) / 60)) }
		end
		if Features.meteorActive() then
			return { ok = false, message = "A Meteor Shower is already on" }
		end
		hostLast = os.clock()
		startMeteor()
		workspace:SetAttribute("MeteorNext", meteorUntil + Config.METEOR.every)
		return { ok = true, message = "Meteor Shower started!" }
	elseif action == "hostTime" then
		if game.PrivateServerOwnerId == 0 or game.PrivateServerOwnerId ~= player.UserId then
			return { ok = false, message = "Only the private server's owner can do that" }
		end
		local times = { day = 14, dusk = 18.3, night = 0 }
		local t = times[req.time]
		if not t then
			return { ok = false }
		end
		game:GetService("Lighting").ClockTime = t
		return { ok = true, message = "Time of day changed" }
	elseif action == "watchAd" then
		local id = Config.PRODUCTS.AD_BAIT
		if id == 0 then
			return { ok = false, message = "Not available" }
		end
		local ok, result = pcall(function()
			local reward = AdService:CreateAdRewardFromDevProductId(id)
			return AdService:ShowRewardedVideoAdAsync(player, reward)
		end)
		-- the reward itself arrives through ProcessReceipt (AD_BAIT) once the video is finished
		return { ok = ok and result == Enum.ShowAdResult.ShowCompleted, message = if ok then nil else "No ad right now, try later" }
	end
	return nil
end

---------------------------------------------------------------- profile extras for the client

function Features.snapshot(player: Player, p, out)
	out.luckLadder = p.luckLadder
	out.trap = p.trap
	out.questStreak = p.questStreak
	out.questMaster = p.questMaster
	out.secret = p.secret
	out.lostStreak = if p.lostStreak and p.lostStreak.day == today() then p.lostStreak.count else nil
	out.lines = p.lines
	out.bucketPlus = player:GetAttribute("BucketPlus") or 0
	out.isHost = game.PrivateServerOwnerId ~= 0 and game.PrivateServerOwnerId == player.UserId
	out.trapPerFish = Config.TRAP.perFish
end

---------------------------------------------------------------- setup

function Features.init(c)
	ctx = c
	makeSpecialModels()
	task.spawn(meteorLoop)
	Players.PlayerRemoving:Connect(function(player)
		fishingAt[player] = nil
		pendingKeep[player] = nil
		lastSale[player] = nil
	end)
	_ = MarketplaceService
end

return Features
