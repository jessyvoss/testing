-- Fish in Space: all game numbers in one place (shared by server and client).
-- Depth and distance are in "sea units" of the 2D fishing view (y = 0 is the surface, down is +).
local C = {}

C.PROFILE_STORE = "FishInSpace_Profile_v1"

-- RARITIES (order matters: higher = rarer)
C.RARITY = {
	Junk = { order = 0, color = Color3.fromRGB(170, 170, 190), name = "Junk" },
	Common = { order = 1, color = Color3.fromRGB(94, 240, 208), name = "Common" },
	Uncommon = { order = 2, color = Color3.fromRGB(115, 166, 255), name = "Uncommon" },
	Rare = { order = 3, color = Color3.fromRGB(255, 95, 200), name = "Rare" },
	Epic = { order = 4, color = Color3.fromRGB(255, 110, 50), name = "Epic" },
}

-- DEPTH LAYERS
C.LAYERS = {
	{ name = "Stardust Shallows", from = 0, to = 360, out = 30, throwLevel = 0, count = 10, xTo = 120, color = Color3.fromRGB(36, 28, 86), weights = { Common = 95, Junk = 5 } },
	{ name = "Nebula Drift", from = 360, to = 840, out = 120, throwLevel = 3, count = 7, xTo = 320, color = Color3.fromRGB(24, 17, 66), weights = { Uncommon = 60, Common = 35, Junk = 5 } },
	{ name = "Asteroid Reef", from = 840, to = 1380, out = 300, throwLevel = 8, count = 4, xTo = 560, color = Color3.fromRGB(15, 9, 44), weights = { Rare = 45, Uncommon = 45, Common = 5, Junk = 5 } },
	{ name = "The Void", from = 1380, to = 2400, out = 520, throwLevel = 16, count = 3, xTo = 800, color = Color3.fromRGB(5, 2, 16), weights = { Epic = 30, Rare = 50, Uncommon = 15, Junk = 5 } },
}
C.TOP_RARITY = { "Common", "Uncommon", "Rare", "Epic" } -- the rarity luck boosts, per layer

function C.layerAt(depth: number): number
	for i, l in C.LAYERS do
		if depth < l.to then
			return i
		end
	end
	return #C.LAYERS
end

-- FISH (value = medium-size sell price in coins)
C.FISH = {
	{ id = "space_guppy", name = "Space Guppy", rarity = "Common", layer = 1, value = 5 },
	{ id = "moon_minnow", name = "Moon Minnow", rarity = "Common", layer = 1, value = 5 },
	{ id = "star_shrimp", name = "Star Shrimp", rarity = "Common", layer = 1, value = 6 },
	{ id = "dust_puffling", name = "Dust Puffling", rarity = "Common", layer = 1, value = 6 },
	{ id = "cosmo_carp", name = "Cosmo Carp", rarity = "Common", layer = 1, value = 8 },
	{ id = "twinkle_tetra", name = "Twinkle Tetra", rarity = "Common", layer = 1, value = 8 },
	{ id = "comet_krill", name = "Comet Krill", rarity = "Common", layer = 1, value = 9 },
	{ id = "orbit_sardine", name = "Orbit Sardine", rarity = "Common", layer = 1, value = 9 },
	{ id = "pebble_crab", name = "Pebble Crab", rarity = "Common", layer = 1, value = 11 },
	{ id = "lunar_loach", name = "Lunar Loach", rarity = "Common", layer = 1, value = 12 },
	{ id = "comet_tail", name = "Comet Tail", rarity = "Uncommon", layer = 2, value = 26 },
	{ id = "nebula_jelly", name = "Nebula Jelly", rarity = "Uncommon", layer = 2, value = 27 },
	{ id = "orbit_eel", name = "Orbit Eel", rarity = "Uncommon", layer = 2, value = 31 },
	{ id = "plasma_perch", name = "Plasma Perch", rarity = "Uncommon", layer = 2, value = 32 },
	{ id = "aurora_angelfish", name = "Aurora Angelfish", rarity = "Uncommon", layer = 2, value = 37 },
	{ id = "rocket_trout", name = "Rocket Trout", rarity = "Uncommon", layer = 2, value = 41 },
	{ id = "saturn_snapper", name = "Saturn Snapper", rarity = "Uncommon", layer = 2, value = 44 },
	{ id = "nova_clownfish", name = "Nova Clownfish", rarity = "Uncommon", layer = 2, value = 49 },
	{ id = "halo_seahorse", name = "Halo Seahorse", rarity = "Uncommon", layer = 2, value = 54 },
	{ id = "crystal_spiker", name = "Crystal Spiker", rarity = "Rare", layer = 3, value = 190 },
	{ id = "meteor_stinger", name = "Meteor Stinger", rarity = "Rare", layer = 3, value = 220 },
	{ id = "rockjaw", name = "Rockjaw", rarity = "Rare", layer = 3, value = 240 },
	{ id = "quasar_lionfish", name = "Quasar Lionfish", rarity = "Rare", layer = 3, value = 260 },
	{ id = "ion_barracuda", name = "Ion Barracuda", rarity = "Rare", layer = 3, value = 290 },
	{ id = "gem_shell_snapper", name = "Gem Shell Snapper", rarity = "Rare", layer = 3, value = 320 },
	{ id = "gravity_eater", name = "Gravity Eater", rarity = "Rare", layer = 3, value = 350 },
	{ id = "void_fang", name = "Void Fang", rarity = "Epic", layer = 4, value = 1900 },
	{ id = "pulsar_reaper", name = "Pulsar Reaper", rarity = "Epic", layer = 4, value = 2300 },
	{ id = "eclipse_leviathan", name = "Eclipse Leviathan", rarity = "Epic", layer = 4, value = 2700 },
	{ id = "event_horizon_eel", name = "Event Horizon Eel", rarity = "Epic", layer = 4, value = 3300 },
}
C.JUNK = {
	{ id = "lost_satellite", name = "Lost Satellite", rarity = "Junk", value = 1 },
	{ id = "astronaut_boot", name = "Astronaut Boot", rarity = "Junk", value = 1 },
	{ id = "cosmic_rubber_duck", name = "Cosmic Rubber Duck", rarity = "Junk", value = 1 },
	{ id = "space_soda_can", name = "Space Soda Can", rarity = "Junk", value = 1 },
}
C.BY_ID = {}
for _, f in C.FISH do
	C.BY_ID[f.id] = f
end
for _, j in C.JUNK do
	C.BY_ID[j.id] = j
end

-- DEPTH BONUS: a fish is worth +1% for every 10m below the top of the area it was caught in, so every
-- Line Length level raises what you earn (up to about +70% at the bottom of The Void). Junk gets none.
C.DEPTH_BONUS = { every = 10, pct = 1 }
function C.depthBonus(id: string, depth: number): number
	local f = C.BY_ID[id]
	if not f or f.rarity == "Junk" then
		return 0
	end
	local L = C.LAYERS[C.layerAt(depth)]
	return math.max(0, math.floor((depth - L.from) / C.DEPTH_BONUS.every) * C.DEPTH_BONUS.pct)
end

-- SIZES: value multiplier and how big it is drawn
C.SIZES = {
	-- (most catches are Medium or bigger, so landing a fish feels good; Tiny and Small pay a bit less to keep
	-- the average about where it was: 0.94x of a Medium, was 0.90x)
	{ name = "Tiny", weight = 16, mult = 0.5, scale = 0.7 },
	{ name = "Small", weight = 26, mult = 0.7, scale = 0.85 },
	{ name = "Medium", weight = 34, mult = 1, scale = 1 },
	{ name = "Large", weight = 18, mult = 1.2, scale = 1.25 },
	{ name = "Huge", weight = 6, mult = 2, scale = 1.6 },
}

-- HOW FISH SWIM, by rarity. Every fish moves, and more so the rarer it is:
--   speed  patrol speed (units per second)       amp/freq  bobbing up and down
--   dart   chance of a quick dash                 drift/sway  how far (units) and how fast (per second)
--   share  how many of that tier patrol            a fish that doesn't patrol sways around its spot
C.MOVE = {
	Junk = { speed = 14, amp = 3, freq = 0.6, dart = 0, drift = 5, sway = 0.22, share = 0.1 },
	Common = { speed = 20, amp = 6, freq = 0.9, dart = 0, drift = 7, sway = 0.3, share = 0.2 },
	Uncommon = { speed = 32, amp = 10, freq = 1.3, dart = 0.12, drift = 10, sway = 0.38, share = 0.35 },
	Rare = { speed = 50, amp = 14, freq = 2.1, dart = 0.35, drift = 13, sway = 0.48, share = 0.5 },
	Epic = { speed = 74, amp = 18, freq = 2.8, dart = 0.8, drift = 16, sway = 0.6, share = 0.7 },
}

-- UPGRADES (costs are per level; level 0 is what you start with)
-- The long tracks are built by track(): each level adds a small step, and each level costs `growth` times the
-- one before (rounded to 2 significant figures), so prices keep pace with what you earn as you go deeper.
-- Tuned with ServerStorage.EconomySim (a simulated player who fishes the deepest area they can reach, sells, buys
-- upgrades, and rebirths once The Void is open). The goal is that something is always within reach:
--   Nebula Drift ~18 min, Asteroid Reef ~1.5 h, The Void ~5 h, first rebirth ~6 h, then a rebirth every ~3-4.5 h.
--   Typical time between purchases: ~1 min in the first hour, ~2 min after; the longest wait (saving up for a
--   rebirth or Star Bait) is ~30 min, ~45 min only after 15+ rebirths.
--   Income per area (no rebirths): ~29, ~67, ~240, ~870 coins a minute, so each area is a real jump.
-- Re-run the sim after changing any of these.
local function nice(x: number): number
	if x < 100 then
		return math.floor(x + 0.5)
	end
	local m = 10 ^ (math.floor(math.log10(x)) - 1)
	return math.floor(x / m + 0.5) * m
end
local function track(levels: number, first: number, growth: number, start: number, step: number, decimals: number?)
	local costs, values = {}, {}
	for n = 1, levels do
		costs[n] = nice(first * growth ^ (n - 1))
	end
	local k = 10 ^ (decimals or 0)
	for n = 0, levels do
		values[n + 1] = math.floor((start + step * n) * k + 0.5) / k
	end
	return costs, values
end
C.track = track

local tetherCosts, tetherValues = track(40, 28, 1.18, 478, 54) -- +54 line a level: Nebula at 2, Reef at 11, Void at 21 (40 reaches the bottom)
local cargoCosts, cargoValues = track(80, 14, 1.108, 5, 1) -- +1 fish a level: 5 -> 85
local throwCosts, throwValues = track(40, 21, 1.225, 420, 13) -- +13 a level: Nebula at 3, Reef at 8, Void at 16
local reelCosts, reelValues = track(40, 35, 1.216, 80, 3) -- +3 reel speed a level: 80 -> 200
local _, reelSink = track(40, 1, 1, 1, 0.02, 3) -- the hook sinks a little faster each level: 1x -> 1.8x
C.UPGRADES = {
	tether = { name = "Line Length", desc = "Longer line: reach deeper layers", costs = tetherCosts, values = tetherValues },
	cargo = { name = "Bucket", desc = "Carry more fish before you sell", costs = cargoCosts, values = cargoValues },
	-- bait stays a few big steps: each one lets a new rarity bite
	lure = { name = "Better Bait", desc = "Fish too rare for your bait won't bite", costs = { 80, 600, 6000 }, values = { 1, 2, 3, 4 }, names = { "Basic Bait", "Glow Bait", "Plasma Bait", "Star Bait" } },
	throw = { name = "Distance Throw", desc = "Rarer fish live farther out", costs = throwCosts, values = throwValues },
	reel = { name = "Hook Modification", desc = "Faster reel and the hook sinks faster", costs = reelCosts, values = reelValues, sink = reelSink },
	hook = { name = "Hook Capacity", desc = "Catch more fish on one cast", costs = { 400, 4000, 20000 }, values = { 1, 2, 3, 4 } },
}
-- shop order follows how you progress: a bigger bucket first (more coins per trip), then what opens the next
-- area (Line Length to sink deeper, Distance Throw to reach farther out, Better Bait so its fish bite), then speed
C.UPGRADE_ORDER = { "cargo", "tether", "throw", "lure", "reel" }

-- What it takes to reach each area (layer): Line Length deep enough, Distance Throw far enough, and bait good
-- enough for its rarest fish. Returns { tether = level, throw = level, lure = level }.
function C.areaNeeds(li: number)
	local L = C.LAYERS[li]
	local need = { tether = 0, throw = L.throwLevel or 0, lure = 0 }
	for lv = 0, #C.UPGRADES.tether.costs do
		if C.UPGRADES.tether.values[lv + 1] + C.CAST.rodTip.Y > L.from + 12 then
			need.tether = lv
			break
		end
	end
	local order = C.RARITY[C.TOP_RARITY[li]].order
	for lv = 0, #C.UPGRADES.lure.costs do
		if C.UPGRADES.lure.values[lv + 1] >= order then
			need.lure = lv
			break
		end
	end
	return need
end

-- Better Bait is a gate: the highest rarity order that bites (1 Common, 2 Uncommon, 3 Rare, 4 Epic; junk always does)
function C.baitMax(level: number): number
	return C.upgradeValue("lure", level or 0)
end

-- ZORP'S FISH QUESTS (the alien by the shop): bring him 1 to 3 of a fish you have already caught
C.CAT_QUEST = {
	minUnique = 4, -- different fish you need to have caught before he trusts you with a quest
	maxCount = 3,
	perUnique = 10, -- reward: perUnique x different fish caught, plus count^2 x valueMult x fish value
	valueMult = 3,
}
-- what the cat says to whoever walks by
C.CAT_LINES = { "Hello!", "Sell your fish to Zorp!", "More coins for bigger fish!", "Zorp has quests for you!", "Deep fish live far out...", "Need better bait for rare fish!" }
-- shouted to the whole server: Epic catches and Huge Rares
C.SHOUT_MIN_ORDER = 4

function C.upgradeValue(key: string, level: number)
	local u = C.UPGRADES[key]
	return u.values[math.clamp(level + 1, 1, #u.values)]
end

-- MUSIC: paste Roblox audio IDs here (Creator Store > Audio > Music, e.g. ambient / chill tracks).
-- The island list plays while walking around; the sea list plays in the 2D fishing view.
C.MUSIC = {
	-- calm tracks from verified uploaders. Each entry is { audio id, gain }: the gain evens out loudness
	-- (measured with Sound.PlaybackLoudness) so quiet tracks aren't near-silent and loud ones don't blast.
	-- Tracks that measured as steady noise (static, rain, "pink noise") were taken out.
	-- one playlist for the whole game: the lobby and fishing play the same music, and it keeps going
	-- (no switch) when you start or stop fishing
	island = {
		{ 115196472299813, 0.5 }, -- afternoon sunlight
		{ 83635869177234, 0.7 }, -- nightwalk
		{ 133867630219725, 1.0 }, -- sad mist love (lo-fi)
	},
	volume = 0.13,
}
C.MUSIC.sea = C.MUSIC.island

-- CASTING AND THE SWING
-- Fishing happens only on the dock at the end of the bridge (the wooden pier in front of the island).
-- Anyone standing on it fishes straight out to sea (+X).
-- Three fishing docks around the island. Walk out along a dock (past FISH_ZONE_START) to fish; when you start,
-- you're moved to the end of the pier facing out to sea.
-- cframe: centre of the dock zone with its local X pointing out to sea; size = X (out) by Z (across).
C.PIERS = {
	{ name = "East", cframe = CFrame.new(132.5, 28.15, 10.6), size = Vector2.new(69.9, 27.6), facing = -90 },
	{ name = "West", cframe = CFrame.new(-132.5, 28.15, -10.6) * CFrame.Angles(0, math.pi, 0), size = Vector2.new(69.9, 27.6), facing = 90 },
	{ name = "South", cframe = CFrame.new(0, 28.15, 104.4) * CFrame.Angles(0, -math.pi / 2, 0), size = Vector2.new(54.4, 27.6), facing = 180 },
}
C.PIER = C.PIERS[1]
-- The fishing prompt starts this far along a dock (0 = where it meets the island, 1 = the end), so it
-- doesn't pop up the moment you step on.
C.FISH_ZONE_START = 0.35

-- The dock a spot is on (or nil). slack widens the zone a little (server lag).
function C.fishPier(pos: Vector3, slack: number?)
	local s = slack or 0
	for _, p in C.PIERS do
		local lp = p.cframe:PointToObjectSpace(pos)
		local startX = -p.size.X / 2 + p.size.X * (C.FISH_ZONE_START or 0) -- the island end of the fishing zone
		if lp.X >= startX - s and lp.X <= p.size.X / 2 + s and math.abs(lp.Z) <= p.size.Y / 2 + s and lp.Y > -3 - s and lp.Y < 8 + s then
			return p
		end
	end
	return nil
end

-- Where to stand to fish from a dock: near the end of the pier, in the middle.
function C.fishSpot(p): Vector3
	return (p.cframe * CFrame.new(p.size.X / 2 - 2.5, 0, 0)).Position
end

-- Facing (degrees, same convention as the old docks: 0 = looking toward -Z) for a spot,
-- or nil when that spot is not on a dock.
function C.fishFacing(pos: Vector3, slack: number?): number?
	local p = C.fishPier(pos, slack)
	return p and p.facing or nil
end

C.CAST = {
	rodTip = Vector2.new(6, -178), -- where the line leaves the rod (sea units: 4 per stud, y = height above the water)
	chargeTime = 1.2, -- seconds of holding for a full-power cast
	minPower = 0.25,
	flightTime = 1.4,
	swing = 0.75, -- (old pendulum swing, unused)
	sinkSpeed = 50, -- how fast the hook drops when you are not reeling (Hook Modification multiplies it)
	drift = 4, -- how fast a sinking hook drifts back toward the dock (slow, so a long throw keeps the hook far out)
	minOut = 30, -- a sinking hook never drifts closer to the dock than this
	passiveReel = 3, -- the line slowly shortens on its own so every cast ends
	tapReel = 5, -- one tap pulls in this much line
	minLine = 178,
	minReach = 420, -- casts land at your Distance Throw (sea units); if the line is too short to get there it reels the hook back in
	hookRadius = 9, -- touch distance for catching
	poolPerLayer = 40, -- (unused: each layer's count is set in LAYERS, like the inspiration game's fixed fish)
	movingShare = 0.25, -- share of fish that patrol back and forth; the rest stay in their spot
	fishMinDepth = 45, -- no fish right under the surface
	fishGap = 60, -- fish keep at least this far apart (sea units)
	pathClear = 30, -- fish stay at least this far to the side of where the hook sinks (patrolling fish: +60)
	seaWidth = 480, -- how far out each layer's fish spread (sea units from the layer's start)
	maxCastSeconds = 180,
}

-- WORLD 2 and passes
C.WORLD2_COST = 750000 -- the end goal: ~6-7 h of fishing The Void after maxing out
C.WORLD2_OPEN = false -- World 2 is under construction: the gate shows that and takes no coins until this is true
-- the Join the Group sign in the lobby: put your Roblox group's ID here (0 = not set up yet)
C.GROUP = { id = 0, joinGift = 250 } -- coins, once per player, for joining through the sign
C.VIP_SELL_BONUS = 0.2
-- the official group: members sell fish for +10%
C.GROUP_ID = 1066574218
C.GROUP_COIN_BONUS = 0.1
C.AUTO_FISH_SKILL = 0.6
-- BADGES: paste each badge's ID here (0 = not created yet: it's simply not awarded)
C.BADGES = {
	WELCOME = 3321109385821311, -- Welcome, Fisher!: finish Zorp's tutorial
	FIRST_CATCH = 1648660331473551, -- First Catch
	VOID = 555078602379521, -- Into The Void: unlock The Void
	EPIC = 1802499158887387, -- Epic Angler: land an Epic fish
	REBORN = 1286759331770876, -- Reborn: first rebirth
}
C.PASSES = { VIP = 2089588758, AUTO_FISH = 2088622875, PLUS_HOOK = 2088970803, DOUBLE_COINS = 2089408903, AUTO_SELL = 2088502804, GOD_ROD = 2088952880, BIG_BUCKET = 2088772879 }
-- Robux prices shown on the lobby displays (set the same prices on the game passes themselves)
C.PASS_PRICES = { DOUBLE_COINS = 399, PLUS_HOOK = 349, AUTO_FISH = 299, AUTO_SELL = 149, BIG_BUCKET = 149, VIP = 199, GOD_ROD = 1499 }
-- Bigger Bucket pass: +50% bucket capacity
C.BIG_BUCKET_BONUS = 0.5
-- God Fishing Rod: every rarity bites, fish are worth +50% (stacks with 2x Coins), the hook reels and sinks
-- 1.5x faster, plus its aura and a magenta line
C.GOD_ROD_SPEED = 1.5
C.GOD_ROD_VALUE = 0.5
-- LUCKY_LURE is the "Rare Boost" product and SERVER_LUCK the "Server Rare Boost" (the keys stay so saved IDs keep working)
C.PRODUCTS = { LUCKY_LURE = 3732125054, SERVER_LUCK = 3732125281, COINS_SMALL = 3732125634, COINS_MEDIUM = 3732125810, COINS_LARGE = 3732126112, STARTER_PACK = 3732126254 }
-- Robux prices to set on the products (for reference; Roblox shows the real price)
C.PRODUCT_PRICES = { LUCKY_LURE = 49, SERVER_LUCK = 199, COINS_SMALL = 39, COINS_MEDIUM = 99, COINS_LARGE = 299, STARTER_PACK = 99 }
-- Starter Pack: one purchase, offered during your first hour of play. A Rare Boost, a medium coin pack and the
-- Starter line color (a cosmetic).
C.STARTER = { seconds = 3600 }
-- fishing line colors: the first one you have wins (catching every fish turns it gold)
C.LINE_COLORS = {
	gold = Color3.fromRGB(255, 205, 90),
	god = Color3.fromRGB(255, 90, 230),
	vip = Color3.fromRGB(90, 235, 255),
	starter = Color3.fromRGB(120, 255, 150),
	default = Color3.fromRGB(225, 215, 255),
}
-- coin packs grow with your progress (x TIER_MULT for the deepest area you've unlocked), so a pack is always
-- worth about the same amount of fishing: ~25 min, ~1.5 h and ~6.5 h of your current income
C.COIN_PACKS = { COINS_SMALL = 750, COINS_MEDIUM = 2500, COINS_LARGE = 11000 }
C.LUCK_BOOST_SECONDS = 15 * 60
-- REBIRTH: once The Void is unlocked, pay the rebirth cost to start over (coins, upgrades and bucket reset; your
-- catalog, stats, quests and passes stay). Each rebirth gives a permanent +35% coins and 1 rebirth token to spend on
-- perks. The cost follows your income (it grows with the +35% coin bonus, plus 8% a time), so saving up for the next
-- rebirth always takes about half an hour of Void fishing, never hours.
-- Pace (simulated, with the rare-fish fight): 1st rebirth ~6 h of play, then ~4.5 h, settling at ~3 h a run.
-- (Before this retune: 100k x1.3 a time gave ~12 h, then ~8 h each, with 1-2 hours of pure saving before each.)
C.REBIRTH = {
	baseCost = 25000,
	growth = 1.08,
	coinBonus = 0.35, -- per rebirth
	needTier = 4, -- The Void
	perks = {
		{ key = "headStart", name = "Head Start", desc = "Start every rebirth with +5 levels of Bucket, Line Length, Distance Throw and Hook Modification", max = 5 },
		{ key = "steady", name = "Steady Hands", desc = "+10% wider catch zone when a rare fish fights", max = 5 },
		{ key = "diver", name = "Deep Diver", desc = "+20% depth bonus on every fish", max = 5 },
		{ key = "lucky", name = "Lucky Charm", desc = "Your area's rarest fish show up 10% more often", max = 5 },
	},
}
C.PERKS = {}
for _, pk in C.REBIRTH.perks do
	C.PERKS[pk.key] = pk
end
function C.rebirthCost(n: number): number
	n = n or 0
	return math.floor(C.REBIRTH.baseCost * (1 + C.REBIRTH.coinBonus * n) * C.REBIRTH.growth ^ n / 1000 + 0.5) * 1000
end
function C.coinMult(rebirths: number): number
	return 1 + C.REBIRTH.coinBonus * (rebirths or 0)
end

-- RARE FISH FIGHT: hooking a Rare or Epic starts a short fight. The fish darts along a bar; hold to push your
-- catch zone right, let go and it drifts left. Fish inside the zone = the catch meter fills, outside = it drains.
-- Full = caught, empty = it breaks free. zone = width of your catch zone (0..1 of the bar; the God Rod and the
-- Steady Hands rebirth perk widen it), speed/calm/dart = how restless the fish is, pull = how hard you pull,
-- gain/drain = meter per second, start = where the meter begins.
C.FIGHT = {
	-- simulated win rates (average player / good player and Auto Fish): Rare ~64% / ~94%, Epic ~48% / ~82%
	-- (made harder: they were ~96% / ~99% and ~63% / ~87%)
	Rare = { zone = 0.28, speed = 1.05, calm = { 0.42, 0.95 }, dart = 0.26, pull = 2.45, gain = 0.39, drain = 0.31, start = 0.34 },
	-- Epic fish also fight differently, so there is something new to learn: feint = chance a big dash is a
	-- fake-out (it starts for the far side, then snaps back); surge = every few seconds it thrashes and moves
	-- surge.mult times faster for surge.time seconds (the bar flashes first so you can react). Its zone is a bit
	-- wider than before to make up for that (re-check the win rate in play tests).
	Epic = { zone = 0.29, speed = 1.25, calm = { 0.38, 0.88 }, dart = 0.31, pull = 2.6, gain = 0.36, drain = 0.3, start = 0.34, feint = 0.4, surge = { every = { 2.6, 4.2 }, warn = 0.35, time = 0.55, mult = 1.9 } },
}
-- after a fish of a rarity gets away, your next fight with that rarity quietly has a wider catch zone
-- (+perLoss each loss in a row, up to max); landing one resets it. Nothing on screen says so.
C.FIGHT_COMFORT = { perLoss = 0.08, max = 3 }
-- catch grades: how long the fish spent outside your zone during the whole fight
C.FIGHT_GRADES = { { name = "PERFECT", maxOutside = 0.35 }, { name = "GREAT", maxOutside = 1.5 } }

-- RARE BOOST (Rare Boost product, Server Rare Boost, day 7 of the streak): your area's rarest kind of fish spawns
-- twice as often. In the Shallows (where the rarest kind is Common) it brings in some Uncommons instead, and while
-- it's on, fish one rarity above your bait still bite, so even a brand-new player gets something exciting.
C.BOOST = { mult = 2, shallowsUncommon = 12 }

-- the layer's spawn weights, with or without a boost
function C.layerWeights(li: number, boosted: boolean, lucky: number?)
	local L = C.LAYERS[li]
	local w = table.clone(L.weights)
	-- Lucky Charm (rebirth perk): +10% a level for the area's rarest kind (Uncommons in the Shallows)
	if lucky and lucky > 0 then
		local topR = C.TOP_RARITY[li]
		if li == 1 then
			w.Uncommon = (w.Uncommon or 0) + 2 * lucky
		elseif w[topR] then
			w[topR] *= 1 + 0.1 * lucky
		end
	end
	if boosted then
		local top = C.TOP_RARITY[li]
		if li == 1 then
			w.Uncommon = (w.Uncommon or 0) + C.BOOST.shallowsUncommon
		elseif w[top] then
			w[top] *= C.BOOST.mult
		end
	end
	return w
end

-- for the HUD: what the boost does in this area, e.g. "EPICS 30% -> 46%" (as text)
function C.boostText(li: number): string
	local function share(w, r)
		local t = 0
		for _, v in w do
			t += v
		end
		return math.floor((w[r] or 0) / t * 100 + 0.5)
	end
	local r = if li == 1 then "Uncommon" else C.TOP_RARITY[li]
	local before, after = share(C.layerWeights(li, false), r), share(C.layerWeights(li, true), r)
	return ("%sS %d%% → %d%%"):format(string.upper(r), before, after)
end

-- QUESTS AND DAILY STREAK (rewards grow with the deepest area you've unlocked, so they stay worth it)
C.TIER_MULT = { 1, 2.3, 8, 30 } -- about how much more each area earns (simulated: ~29, ~67, ~240, ~870 coins a minute)

-- the deepest area these upgrades can fish in (Line Length, Distance Throw and bait all far enough)
function C.tierOf(upgrades): number
	local best = 1
	for li = 2, #C.LAYERS do
		local n = C.areaNeeds(li)
		if (upgrades.tether or 0) >= n.tether and (upgrades.throw or 0) >= n.throw and (upgrades.lure or 0) >= n.lure then
			best = li
		end
	end
	return best
end
function C.tierMult(upgrades): number
	return C.TIER_MULT[math.clamp(C.tierOf(upgrades), 1, #C.TIER_MULT)]
end
function C.coinPack(key: string, upgrades): number
	return math.floor((C.COIN_PACKS[key] or 0) * C.tierMult(upgrades))
end
-- Daily quests (3 a day). minTier = the area you need to have unlocked for it to come up (1 Shallows, 2 Nebula,
-- 3 Reef, 4 Void), so you're never given one you can't do. Coins are x the area multiplier.
C.QUESTS = {
	daily = {
		{ id = "d_catch", text = "Catch %d fish", stat = "catch", goal = 30, coins = 250 },
		{ id = "d_huge", text = "Land %d Huge fish", stat = "huge", goal = 1, coins = 250 },
		{ id = "d_sell", text = "Earn %d coins from selling", stat = "sell", goal = 300, coins = 200, scaleGoal = true },
		{ id = "d_casts", text = "Cast %d times", stat = "cast", goal = 25, coins = 200 },
		{ id = "d_uncommon", text = "Catch %d Uncommon or rarer fish", stat = "uncommon", goal = 6, coins = 300, minTier = 2 },
		{ id = "d_rare", text = "Catch %d Rare or rarer fish", stat = "rare", goal = 4, coins = 350, minTier = 3 },
	},
	dailyCount = 3,
}
C.STREAK = { 100, 150, 250, 400, 600, 900, 1500 } -- x the area multiplier; day 7 also gives a Rare Boost

---------------------------------------------------------------- FEATURES (Nov 2026 update; the code lives in
-- ServerScriptService.FishInSpace.Features and FishClient.Features). Every number here is a starting guess:
-- check it in play tests and the Creator Dashboard, and change it here.

-- VISION: "Cozy cosmic fishing with thrilling catches." New features should be relaxing to do and exciting when a
-- big fish bites. If a feature makes the game stressful or pushy, it doesn't fit.

-- METEOR SHOWER: a free server-wide event. Announced `warn` seconds ahead; while it's on, every area's rarest fish
-- show up twice as often for everyone (like a Rare Boost) and meteors fill the sky. In a private server the owner
-- can start one from Settings (once every hostCooldown seconds).
C.METEOR = { every = 40 * 60, duration = 6 * 60, warn = 120, firstDelay = 8 * 60, hostCooldown = 15 * 60 }

-- PROMO CODES (Settings > Codes). The code is matched in upper case. coins are x the area multiplier.
-- Add codes for TikTok / Discord / updates here; remove old ones when they expire.
C.CODES = {
	FISHINSPACE = { coins = 300 },
	ZORP = { coins = 150, boostMin = 5 },
}

-- HOLIDAY FISH: only bite between from and to ({ month, day }, inclusive; to may be in the next year). Once caught they
-- stay in your catalog for good. base = the fish whose model and picture they use, tinted with tint.
-- chance = how often a fish in that area is the holiday fish instead.
C.HOLIDAY_FISH = {
	{ id = "ghost_guppy", name = "Ghost Guppy", base = "space_guppy", rarity = "Uncommon", layer = 1, value = 70, tint = Color3.fromRGB(205, 235, 255), from = { 10, 15 }, to = { 11, 7 }, chance = 0.08 },
	{ id = "snow_comet", name = "Snow Comet", base = "comet_tail", rarity = "Rare", layer = 2, value = 420, tint = Color3.fromRGB(235, 248, 255), from = { 12, 10 }, to = { 1, 6 }, chance = 0.06 },
	{ id = "heart_jelly", name = "Heart Jelly", base = "nebula_jelly", rarity = "Rare", layer = 2, value = 400, tint = Color3.fromRGB(255, 120, 170), from = { 2, 7 }, to = { 2, 21 }, chance = 0.06 },
}
-- THE SECRET FISH: catch all four kinds of space junk and a signal appears in The Void. After that the Golden
-- Leviathan can bite there (chance per Void fish). It isn't on the catalog's checklist, so nobody needs it for 100%.
C.SECRET_FISH = { id = "golden_leviathan", name = "Golden Leviathan", base = "eclipse_leviathan", rarity = "Epic", layer = 4, value = 12000, tint = Color3.fromRGB(255, 205, 70), chance = 0.04 }
C.SPECIAL_FISH = {}
for _, f in C.HOLIDAY_FISH do
	f.special = true
	table.insert(C.SPECIAL_FISH, f)
end
C.SECRET_FISH.special = true
table.insert(C.SPECIAL_FISH, C.SECRET_FISH)
for _, f in C.SPECIAL_FISH do
	C.BY_ID[f.id] = f
end

-- is a { month, day } window open on this date (UTC)?
function C.holidayOpen(f, t: number?): boolean
	local d = os.date("!*t", t or os.time())
	local now = d.month * 100 + d.day
	local a, b = f.from[1] * 100 + f.from[2], f.to[1] * 100 + f.to[2]
	if a <= b then
		return now >= a and now <= b
	end
	return now >= a or now <= b -- wraps over New Year
end

-- CRAFTING (Zorp's Workshop): turn fish from your bucket into something useful, so WHICH fish you catch matters.
-- needs = fish id -> count (any size). reward: boostMin = Rare Boost minutes, coinsMult = coins worth N x the
-- fish used, line = a fishing line color (kept for good), coins = coins x the area multiplier.
C.RECIPES = {
	{ id = "crystal_lure", name = "Crystal Lure", desc = "15 minutes of Rare Boost", needs = { crystal_spiker = 3 }, reward = { boostMin = 15 } },
	{ id = "comet_feast", name = "Comet Feast", desc = "Zorp pays 3x what these fish are worth", needs = { comet_tail = 2, nebula_jelly = 2 }, reward = { coinsMult = 3 } },
	{ id = "junk_sculpture", name = "Junk Sculpture", desc = "Space art! Zorp pays 400 coins (x your area)", needs = { lost_satellite = 1, astronaut_boot = 1, cosmic_rubber_duck = 1, space_soda_can = 1 }, reward = { coins = 400 } },
	{ id = "void_line", name = "Void Line", desc = "A dark purple fishing line, yours to keep", needs = { void_fang = 1, pulsar_reaper = 1 }, reward = { line = "void" } },
}

-- SURPRISES: now and then a caught fish has a pearl inside (bonus coins = mult x its value). Not announced
-- beforehand on purpose (surprise rewards keep fishing fun; promised ones can make it feel like a chore).
C.SURPRISE = { chance = 0.02, mult = 4 }

-- QUEST MASTER: claim all of your daily quests 7 days in a row for the Quest Master line (kept for good).
C.QUEST_STREAK = { days = 7 }

-- REBIRTH LINES: new line colors as you rebirth (variety for each tier)
C.REBIRTH_LINES = { { at = 3, key = "nova" }, { at = 10, key = "supernova" } }
C.LINE_COLORS.master = Color3.fromRGB(110, 255, 200)
C.LINE_COLORS.void = Color3.fromRGB(150, 70, 255)
C.LINE_COLORS.nova = Color3.fromRGB(255, 150, 60)
C.LINE_COLORS.supernova = Color3.fromRGB(255, 250, 220)

-- DEEP-SPACE TRAP: set it before you log off; it catches one fish every perFish seconds from the deepest area you
-- can fish (up to maxFish, and only as many as fit in your bucket when you collect).
C.TRAP = { perFish = 30 * 60, maxFish = 16 }

-- THE ABYSS: the bottom of The Void. Fish caught below `from` are worth +bonusPct more, but the space shark hunts there
-- twice as often.
C.ABYSS = { from = 2150, bonusPct = 25 }
-- SPACE SHARK: while you reel a fish up through these areas a shark may come for it. Reel it out of the area (or
-- above `escape` depth) before it reaches your hook, or it takes one fish. chance = per cast with a fish on the hook.
C.SHARK = { layers = { [3] = true, [4] = true }, chance = 0.3, speed = 95, startDelay = { 0.6, 2.2 }, escape = 840 }

-- FISHING CREW: each other player fishing from the same dock adds bonusPct to your catches (up to max).
C.CREW = { bonusPct = 5, max = 15 }

-- MOMENT-OF-NEED PRODUCTS (create these developer products in the Creator Dashboard and paste their IDs here; while
-- an ID is 0 the offer simply doesn't appear):
--   KEEP_FISH       right after a Rare/Epic gets away: land it after all
--   DOUBLE_SALE     right after you sell: the same coins again
--   BUCKET_PLUS     when your bucket is full: +BUCKET_PLUS slots until you leave the server
--   STREAK_RESTORE  the day your daily streak breaks: carry on where you were
--   LUCK_1..LUCK_5  the Luck Upgrade ladder: each level +LUCK_LADDER.pct% for your area's rarest fish (permanent)
--   AD_BAIT         the reward for a rewarded video ad: LUCK_BOOST_AD minutes of Rare Boost
C.PRODUCTS.KEEP_FISH = 0
C.PRODUCTS.DOUBLE_SALE = 0
C.PRODUCTS.BUCKET_PLUS = 0
C.PRODUCTS.STREAK_RESTORE = 0
C.PRODUCTS.LUCK_1, C.PRODUCTS.LUCK_2, C.PRODUCTS.LUCK_3, C.PRODUCTS.LUCK_4, C.PRODUCTS.LUCK_5 = 0, 0, 0, 0, 0
C.PRODUCTS.AD_BAIT = 0
C.PRODUCT_PRICES.KEEP_FISH = 29
C.PRODUCT_PRICES.DOUBLE_SALE = 19
C.PRODUCT_PRICES.BUCKET_PLUS = 25
C.PRODUCT_PRICES.STREAK_RESTORE = 25
C.PRODUCT_PRICES.LUCK_1, C.PRODUCT_PRICES.LUCK_2, C.PRODUCT_PRICES.LUCK_3, C.PRODUCT_PRICES.LUCK_4, C.PRODUCT_PRICES.LUCK_5 = 9, 19, 29, 49, 79
C.BUCKET_PLUS = 20
C.LUCK_LADDER = { pct = 5, max = 5 }
C.LUCK_BOOST_AD = 5 -- minutes
C.KEEP_FISH_SECONDS = 20 -- how long the "keep it" offer stays up
C.DOUBLE_SALE_SECONDS = 20

-- IN-WORLD OUTLINES: a soft dark outline on the main characters and stands, to match the toon HUD icons
-- (Highlights; Roblox draws at most ~31 at once). Off in Low Graphics.
C.OUTLINES = { enabled = true, color = Color3.fromRGB(20, 10, 40), names = { "QuestAlien", "Merchant", "PassStands" } }

return C
