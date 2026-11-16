-- Fish in Space: player save data. Loads/saves with DataStores; if those are unavailable
-- (Studio without API access) the game still runs, it just doesn't save.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.FishInSpace.Config)

local Profiles = {}
local data: { [Player]: any } = {}
local dirty: { [Player]: boolean } = {}

local store
pcall(function()
	store = DataStoreService:GetDataStore(Config.PROFILE_STORE)
end)

local function today(): number
	return math.floor(os.time() / 86400)
end
Profiles.today = today

local function newProfile()
	return {
		coins = 0,
		earned = 0, -- all coins ever earned from selling
		upgrades = { tether = 0, hook = 0, cargo = 0, lure = 0, reel = 0, throw = 0 },
		fishQuest = nil, -- { id = fish id, need = 1..3, have = n, reward = coins } from the cat
		cargo = {}, -- { {id = "space_guppy", size = 3}, ... }
		catalog = {}, -- [id] = { best = sizeIndex, count = n }
		stats = { caught = 0, casts = 0, biggest = 0, rare = 0 },
		quests = {},
		streak = { day = 0, count = 0 },
		world2 = false,
		luckUntil = 0,
		tutorialDone = false,
		settings = {}, -- the client's Settings window (see FishClient.Settings)
		rebirths = 0,
		tokens = 0, -- rebirth tokens to spend on perks
		perks = {}, -- [perk key] = level
		playSeconds = 0, -- total time played (the Starter Pack is offered for the first hour)
		starterBought = false,
		starterLine = false, -- the Starter Pack's line color
		groupGift = false, -- got the Join the Group welcome coins
		questsUnlocked = false, -- Zorp has given you a quest (the catch-4-kinds starter quest is done)
	}
end

-- only known settings with the right type survive
local SETTINGS = { music = "number", sfx = "number", auras = "string", lowGfx = "boolean", hidePlayers = "boolean", announce = "boolean", autoTargets = "string" }
function Profiles.cleanSettings(raw)
	local out = {}
	if typeof(raw) ~= "table" then
		return out
	end
	for k, t in SETTINGS do
		local v = raw[k]
		if typeof(v) == t then
			if t == "number" then
				v = math.clamp(v, 0, 1)
				if v ~= v then
					v = 1
				end
			elseif k == "auras" and v ~= "all" and v ~= "mine" and v ~= "off" then
				v = nil
			elseif k == "autoTargets" and (#v > 40 or v:find("[^%a,]")) then
				v = nil
			end
			out[k] = v
		end
	end
	return out
end

local function sanitize(raw)
	local p = newProfile()
	if typeof(raw) ~= "table" then
		return p
	end
	p.coins = math.max(0, math.floor(tonumber(raw.coins) or 0))
	p.earned = math.max(0, math.floor(tonumber(raw.earned) or 0))
	if typeof(raw.upgrades) == "table" then
		for key, u in Config.UPGRADES do
			p.upgrades[key] = math.clamp(math.floor(tonumber(raw.upgrades[key]) or 0), 0, #u.costs)
		end
	end
	if typeof(raw.cargo) == "table" then
		for _, c in raw.cargo do
			if typeof(c) == "table" and Config.BY_ID[c.id] then
				table.insert(p.cargo, { id = c.id, size = math.clamp(math.floor(tonumber(c.size) or 1), 1, #Config.SIZES), bonus = math.clamp(math.floor(tonumber(c.bonus) or 0), 0, 200) })
			end
		end
	end
	if typeof(raw.catalog) == "table" then
		for id, e in raw.catalog do
			if Config.BY_ID[id] and typeof(e) == "table" then
				p.catalog[id] = { best = math.clamp(math.floor(tonumber(e.best) or 1), 1, #Config.SIZES), count = math.max(1, math.floor(tonumber(e.count) or 1)) }
			end
		end
	end
	if typeof(raw.stats) == "table" then
		p.stats.caught = math.max(0, math.floor(tonumber(raw.stats.caught) or 0))
		p.stats.casts = math.max(0, math.floor(tonumber(raw.stats.casts) or 0))
		p.stats.biggest = math.max(0, math.floor(tonumber(raw.stats.biggest) or 0))
		p.stats.rare = math.max(0, math.floor(tonumber(raw.stats.rare) or 0))
	end
	if typeof(raw.quests) == "table" then
		p.quests = raw.quests
	end
	if typeof(raw.streak) == "table" then
		p.streak = { day = tonumber(raw.streak.day) or 0, count = tonumber(raw.streak.count) or 0 }
	end
	p.world2 = raw.world2 == true
	p.luckUntil = tonumber(raw.luckUntil) or 0
	p.tutorialDone = raw.tutorialDone == true
	p.settings = Profiles.cleanSettings(raw.settings)
	p.playSeconds = math.max(0, math.floor(tonumber(raw.playSeconds) or 0))
	p.rebirths = math.max(0, math.floor(tonumber(raw.rebirths) or 0))
	p.tokens = math.max(0, math.floor(tonumber(raw.tokens) or 0))
	if typeof(raw.perks) == "table" then
		for key, pk in Config.PERKS do
			local lv = math.floor(tonumber(raw.perks[key]) or 0)
			if lv > 0 then
				p.perks[key] = math.clamp(lv, 0, pk.max)
			end
		end
	end
	p.starterBought = raw.starterBought == true
	p.starterLine = raw.starterLine == true
	p.groupGift = raw.groupGift == true
	p.questsUnlocked = raw.questsUnlocked == true or typeof(raw.fishQuest) == "table"
	if typeof(raw.fishQuest) == "table" and Config.BY_ID[raw.fishQuest.id] then
		local need = math.clamp(math.floor(tonumber(raw.fishQuest.need) or 1), 1, Config.CAT_QUEST.maxCount)
		local have = math.clamp(math.floor(tonumber(raw.fishQuest.have) or (if raw.fishQuest.caught == true then need else 0)), 0, need)
		p.fishQuest = { id = raw.fishQuest.id, need = need, have = have, reward = math.max(0, math.floor(tonumber(raw.fishQuest.reward) or 0)) }
		if typeof(raw.fishQuest.sid) == "string" then
			p.fishQuest.sid = raw.fishQuest.sid:sub(1, 64) -- (the quest's analytics funnel id)
		end
	end
	return p
end

function Profiles.load(player: Player)
	local raw
	if store then
		local ok, result = pcall(store.GetAsync, store, "p_" .. player.UserId)
		if ok then
			raw = result
		else
			warn("[FishInSpace] Could not load data (saving is off in Studio unless API access is on):", result)
		end
	end
	data[player] = sanitize(raw)
	return data[player]
end

function Profiles.get(player: Player)
	return data[player]
end

function Profiles.markDirty(player: Player)
	dirty[player] = true
end

function Profiles.save(player: Player)
	local p = data[player]
	if not p or not store or not dirty[player] then
		return
	end
	dirty[player] = nil
	local ok, err = pcall(store.SetAsync, store, "p_" .. player.UserId, p)
	if not ok then
		dirty[player] = true
		warn("[FishInSpace] Save failed:", err)
	end
end

function Profiles.unload(player: Player)
	Profiles.save(player)
	data[player] = nil
	dirty[player] = nil
end

function Profiles.addCoins(player: Player, n: number): number
	local p = data[player]
	if not p then
		return 0
	end
	p.coins = math.max(0, p.coins + math.floor(n))
	dirty[player] = true
	player:SetAttribute("Coins", p.coins)
	return p.coins
end

-- every 60s, and when the server shuts down
task.spawn(function()
	while true do
		task.wait(60)
		for player in data do
			task.spawn(Profiles.save, player)
		end
	end
end)
game:BindToClose(function()
	for player in data do
		Profiles.save(player)
	end
end)

return Profiles
