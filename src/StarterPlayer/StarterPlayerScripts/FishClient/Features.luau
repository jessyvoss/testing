-- Fish in Space: client side of the Nov 2026 features (server side: ServerScriptService.FishInSpace.Features).
--   * HUD: the Meteor Shower countdown, your next goal while fishing, SELL markers over Zorp when your bucket is full
--   * Zorp's Workshop window (side button): the deep-space trap, crafting, the Luck Upgrade ladder, a free boost
--     for watching a video, and your Quest Master progress
--   * Settings: promo codes, and private-server host controls (Meteor Shower, time of day)
--   * offers at the moment they help: keep a fish that got away, double a sale, bucket space, restore a streak
--   * the rebirth celebration, surprise pearls, the secret signal, meteors in the sky, and in-world outlines
-- The main client script (FishClient) calls in here; nothing in here changes how fishing itself works.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("FishInSpace")
local Config = require(Shared:WaitForChild("Config"))
local Art = require(Shared:WaitForChild("Art"))
local Remotes = Shared:WaitForChild("Remotes")
local Ui = require(script.Parent:WaitForChild("Ui"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local Settings = require(script.Parent:WaitForChild("Settings"))

local player = Players.LocalPlayer
local Features = {}

local Menus -- set in init
local profile = nil
local fishing = false
local gui: ScreenGui
local meteorLabel: TextLabel
local goalLabel: TextLabel
local offerCard: ImageLabel?
local lastOffer: { [string]: number } = {}

local function toast(text: string, color: Color3?)
	if Menus then
		Menus.toast(text, color)
	end
end

local function request(req)
	local ok, res = pcall(Remotes.Shop.InvokeServer, Remotes.Shop, req)
	return if ok then res else nil
end

local function fmtTime(s: number): string
	s = math.max(0, math.floor(s))
	if s >= 3600 then
		return ("%dh %02dm"):format(s // 3600, (s % 3600) // 60)
	end
	return ("%d:%02d"):format(s // 60, s % 60)
end

local function serverNow(): number
	if profile and profile.now then
		return profile.now + (os.clock() - (profile._at or os.clock()))
	end
	return os.time()
end

---------------------------------------------------------------- offers (bottom-centre card with a buy button)

local function closeOffer()
	if offerCard then
		offerCard:Destroy()
		offerCard = nil
	end
end

-- key: the product key in Config.PRODUCTS; cooldown: don't offer the same thing more often than this
local function offer(key: string, title: string, sub: string, seconds: number, cooldown: number?)
	local id = Config.PRODUCTS[key] or 0
	if id == 0 then
		return
	end
	if lastOffer[key] and os.clock() - lastOffer[key] < (cooldown or 0) then
		return
	end
	lastOffer[key] = os.clock()
	closeOffer()
	local card = Ui.panel(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -170), Size = UDim2.fromOffset(460, 110), ZIndex = 40 }, true)
	offerCard = card
	Ui.label(card, { Text = title, Font = Ui.TITLE, TextSize = 20, TextColor3 = Ui.GOLD, Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -40, 0, 26), ZIndex = 41 })
	Ui.label(card, { Text = sub, Font = Ui.BODY, TextSize = 15, TextColor3 = Ui.MUTED, TextWrapped = true, Position = UDim2.fromOffset(20, 40), Size = UDim2.new(1, -200, 0, 40), ZIndex = 41 })
	local buy = Ui.button(card, ("%d R$"):format(Config.PRODUCT_PRICES[key] or 0), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -18, 0.5, 6), Size = UDim2.fromOffset(150, 50), ZIndex = 41 }, true)
	local no = Ui.button(card, "NO THANKS", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 8), Size = UDim2.fromOffset(110, 26), ZIndex = 41 })
	Ui.setStyle(no, "grey")
	local t = no:FindFirstChild("Text") :: TextLabel
	if t then
		t.TextSize = 12
	end
	buy.Activated:Connect(function()
		local sig = Remotes:FindFirstChild("AnalyticsSignal")
		if sig then
			sig:FireServer("promptShown")
		end
		MarketplaceService:PromptProductPurchase(player, id)
		closeOffer()
	end)
	no.Activated:Connect(closeOffer)
	Ui.pop(card)
	task.delay(seconds, function()
		if offerCard == card then
			closeOffer()
		end
	end)
end

---------------------------------------------------------------- next goal (while fishing)

local function nextGoalText(p): string?
	local tier = Config.tierOf(p.upgrades)
	if tier >= #Config.LAYERS then
		if (p.rebirths or 0) == 0 or p.coins < (p.rebirthCost or 0) then
			return ("NEXT: REBIRTH  ·  %s / %s COINS"):format(Ui.coinText(p.coins), Ui.coinText(p.rebirthCost or Config.rebirthCost(p.rebirths or 0)))
		end
		return nil
	end
	local L = Config.LAYERS[tier + 1]
	local n = Config.areaNeeds(tier + 1)
	local parts = {}
	local function part(name, have, need)
		table.insert(parts, ("%s %d/%d%s"):format(name, math.min(have, need), need, if have >= need then " ✓" else ""))
	end
	part("LINE", p.upgrades.tether or 0, n.tether)
	part("THROW", p.upgrades.throw or 0, n.throw)
	local baitName = Config.UPGRADES.lure.names[n.lure + 1] or "BAIT"
	table.insert(parts, string.upper(baitName) .. (if (p.upgrades.lure or 0) >= n.lure then " ✓" else " ✗"))
	return "NEXT: " .. string.upper(L.name) .. "  ·  " .. table.concat(parts, "  ·  ")
end

local function updateGoal()
	if not goalLabel then
		return
	end
	local text = profile and fishing and nextGoalText(profile)
	goalLabel.Visible = text ~= nil
	goalLabel.Text = text or ""
end

---------------------------------------------------------------- SELL markers over Zorp

local markers = {}
local function updateMarkers()
	local full = profile ~= nil and #profile.cargo >= profile.cargoCap and not fishing
	local world = workspace:FindFirstChild("World")
	if not world then
		return
	end
	if full and #markers == 0 then
		for _, z in world:GetDescendants() do
			if z.Name == "QuestAlien" and z:IsA("Model") then
				local part = z.PrimaryPart or z:FindFirstChildWhichIsA("BasePart", true)
				if part then
					local bb = Instance.new("BillboardGui")
					bb.Name = "SellMarker"
					bb.Size = UDim2.fromOffset(150, 56)
					bb.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
					bb.AlwaysOnTop = true
					bb.LightInfluence = 0
					bb.MaxDistance = 400
					bb.Adornee = part
					local l = Ui.label(bb, { Text = "SELL HERE", Font = Ui.TITLE, TextSize = 26, TextColor3 = Ui.GOLD, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1) })
					l.TextStrokeTransparency = 0.2
					bb.Parent = gui
					table.insert(markers, bb)
					-- a gentle bob so it catches the eye
					TweenService:Create(bb, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { StudsOffsetWorldSpace = Vector3.new(0, 10.2, 0) }):Play()
				end
			end
		end
	elseif not full and #markers > 0 then
		for _, m in markers do
			m:Destroy()
		end
		table.clear(markers)
	end
end

---------------------------------------------------------------- meteor shower (HUD + sky)

local meteorFolder = Instance.new("Folder")
meteorFolder.Name = "MeteorShower"
local lastStreak = 0
local function meteorStreak()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local centre = cam.CFrame.Position + Vector3.new(math.random(-260, 260), math.random(160, 260), math.random(-260, 260))
	local dir = Vector3.new(math.random() - 0.5, -0.45, math.random() - 0.5).Unit
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 170, 90)
	p.Size = Vector3.new(1.4, 1.4, 1.4)
	p.Shape = Enum.PartType.Ball
	p.Position = centre
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.6, 0)
	a1.Position = Vector3.new(0, -0.6, 0)
	a0.Parent, a1.Parent = p, p
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Lifetime = 0.6
	tr.LightEmission = 1
	tr.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 90, 60))
	tr.Transparency = NumberSequence.new(0, 1)
	tr.Parent = p
	p.Parent = meteorFolder
	local tw = TweenService:Create(p, TweenInfo.new(1.6, Enum.EasingStyle.Linear), { Position = centre + dir * 320 })
	tw:Play()
	task.delay(2.4, function()
		p:Destroy()
	end)
end

local function updateMeteor(now: number)
	local untilT = workspace:GetAttribute("MeteorUntil") or 0
	local nextT = workspace:GetAttribute("MeteorNext") or 0
	if now < untilT then
		meteorLabel.Visible = true
		meteorLabel.Text = "☄ METEOR SHOWER!  RARE FISH x2  ·  " .. fmtTime(untilT - now)
		meteorLabel.TextColor3 = Color3.fromRGB(255, 170, 90)
		if os.clock() - lastStreak > (if Settings.get("lowGfx") then 0.9 else 0.3) then
			lastStreak = os.clock()
			meteorStreak()
		end
	elseif nextT > now and nextT - now <= Config.METEOR.warn then
		meteorLabel.Visible = true
		meteorLabel.Text = "☄ METEOR SHOWER IN " .. fmtTime(nextT - now)
		meteorLabel.TextColor3 = Ui.GOLD
	else
		meteorLabel.Visible = false
	end
end

---------------------------------------------------------------- rebirth celebration

function Features.onRebirth(msg)
	local n = msg.n or 1
	local layer = Ui.gui("RebirthFanfare", 50)
	local dim = Ui.frame(layer, { BackgroundTransparency = 1, BackgroundColor3 = Color3.fromRGB(8, 4, 20), Size = UDim2.fromScale(1, 1) })
	TweenService:Create(dim, TweenInfo.new(0.4), { BackgroundTransparency = 0.25 }):Play()
	local title = Ui.label(layer, { Text = ("REBIRTH %d"):format(n), Font = Ui.TITLE, TextSize = 72, TextColor3 = Ui.GOLD, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromOffset(800, 90) })
	Ui.pop(title)
	local lines = {
		{ "Coins x" .. ("%.2f"):format(Config.coinMult(n)) .. " forever", Ui.GREEN },
		{ "+1 perk token to spend", Ui.CYAN },
		{ "Coins, bucket and upgrades start fresh", Ui.MUTED },
		{ "Your catalog, quests and passes stay", Ui.MUTED },
	}
	for _, rb in Config.REBIRTH_LINES do
		if rb.at == n then
			table.insert(lines, 2, { "New fishing line unlocked!", Config.LINE_COLORS[rb.key] })
		end
	end
	for i, l in lines do
		local lbl = Ui.label(layer, { Text = l[1], Font = Ui.TECH, TextSize = 26, TextColor3 = l[2], TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.46, (i - 1) * 40), Size = UDim2.fromOffset(800, 34), TextTransparency = 1 })
		task.delay(0.35 + i * 0.3, function()
			TweenService:Create(lbl, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
			Sounds.play("coin", { pitch = 1 + i * 0.12 })
		end)
	end
	Sounds.play("sparkle", { pitch = 0.8 })
	task.delay(4.2, function()
		for _, d in layer:GetDescendants() do
			if d:IsA("TextLabel") then
				TweenService:Create(d, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			end
		end
		TweenService:Create(dim, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		task.wait(0.6)
		layer:Destroy()
	end)
end

---------------------------------------------------------------- line color

-- the best line you own wins (the all-fish gold line is handled by FishingView on top of this)
function Features.lineColor(p): Color3
	local LC = Config.LINE_COLORS
	local passes = p.passes or {}
	if passes.GOD_ROD then
		return LC.god
	end
	local rb = p.rebirths or 0
	for i = #Config.REBIRTH_LINES, 1, -1 do
		local r = Config.REBIRTH_LINES[i]
		if rb >= r.at and r.key == "supernova" then
			return LC.supernova
		end
	end
	if p.questMaster then
		return LC.master
	end
	if p.lines and p.lines.void then
		return LC.void
	end
	for i = #Config.REBIRTH_LINES, 1, -1 do
		local r = Config.REBIRTH_LINES[i]
		if rb >= r.at then
			return LC[r.key]
		end
	end
	if passes.VIP then
		return LC.vip
	end
	if p.starterLine then
		return LC.starter
	end
	return LC.default
end

---------------------------------------------------------------- Zorp's Workshop window

local workshopBody: ScrollingFrame
local function clear(f: Instance)
	for _, c in f:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function section(order: number, title: string, sub: string, height: number?): Frame
	local r = Ui.frame(workshopBody, { LayoutOrder = order, BackgroundTransparency = 0.5, BackgroundColor3 = Color3.fromRGB(30, 22, 70), Size = UDim2.new(1, -8, 0, height or 84) })
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = r
	Ui.label(r, { Text = string.upper(title), Font = Ui.TECH, TextSize = 19, Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -230, 0, 24) })
	Ui.label(r, { Name = "Sub", Text = sub, Font = Ui.BODY, TextSize = 14, TextColor3 = Ui.MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(16, 36), Size = UDim2.new(1, -230, 1, -42) })
	return r
end

local function sideButton(r: Frame, text: string, primary: boolean?, onClick: () -> ()): ImageButton
	local b = Ui.button(r, text, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(190, 46) }, primary)
	local t = b:FindFirstChild("Text") :: TextLabel
	if t then
		t.TextSize = 16
	end
	b.Activated:Connect(onClick)
	return b
end

local function cargoCount(id: string): number
	local n = 0
	for _, c in (profile and profile.cargo or {}) do
		if c.id == id then
			n += 1
		end
	end
	return n
end

local renderWorkshop
local function act(req)
	local res = request(req)
	if res then
		toast(res.message or "", if res.ok then Ui.GOLD else Ui.RED)
		if res.ok and res.caught then
			Menus.showCatch(res.caught)
		end
	end
	task.delay(0.3, renderWorkshop)
	return res
end

renderWorkshop = function()
	if not workshopBody or not profile then
		return
	end
	clear(workshopBody)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = workshopBody
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	-- the trap
	local now = serverNow()
	if profile.trap then
		local per = profile.trapPerFish or Config.TRAP.perFish
		local n = math.min(math.floor((now - profile.trap.t) / per), Config.TRAP.maxFish)
		local sub = if n > 0 then ("It has caught %d fish so far (up to %d). Collect when your bucket has room."):format(n, Config.TRAP.maxFish) else ("Out at sea. First fish in about %d min."):format(math.ceil((per - (now - profile.trap.t)) / 60))
		local r = section(nextOrder(), "Deep-Space Trap", sub)
		sideButton(r, "COLLECT", n > 0, function()
			act({ action = "trap" })
		end)
	else
		local r = section(nextOrder(), "Deep-Space Trap", ("Set it before you go: it catches a fish every %d min from your deepest area (up to %d)."):format(Config.TRAP.perFish // 60, Config.TRAP.maxFish))
		sideButton(r, "SET TRAP", true, function()
			act({ action = "trap" })
		end)
	end

	-- crafting
	Ui.label(workshopBody, { LayoutOrder = nextOrder(), Text = "CRAFTING  ·  uses fish from your bucket", Font = Ui.TITLE, TextSize = 15, TextColor3 = Ui.CYAN, Size = UDim2.new(1, -8, 0, 28), TextYAlignment = Enum.TextYAlignment.Bottom })
	for _, rc in Config.RECIPES do
		local needs, ready = {}, true
		for id, n in rc.needs do
			local have = cargoCount(id)
			ready = ready and have >= n
			table.insert(needs, ("%s %d/%d"):format(Config.BY_ID[id].name, math.min(have, n), n))
		end
		local owned = rc.reward.line and profile.lines and profile.lines[rc.reward.line]
		local r = section(nextOrder(), rc.name, rc.desc .. "\nNeeds: " .. table.concat(needs, ", "), 92)
		sideButton(r, if owned then "OWNED" else "CRAFT", ready and not owned, function()
			if not owned then
				act({ action = "craft", id = rc.id })
			end
		end)
	end

	-- the Luck Upgrade ladder (Robux)
	local lv = profile.luckLadder or 0
	local nextKey = "LUCK_" .. (lv + 1)
	if (Config.PRODUCTS[nextKey] or 0) ~= 0 then
		local r = section(nextOrder(), ("Luck Upgrade  %d / %d"):format(lv, Config.LUCK_LADDER.max), ("Each level: your area's rarest fish show up %d%% more often. Permanent."):format(Config.LUCK_LADDER.pct))
		sideButton(r, ("LEVEL %d · %d R$"):format(lv + 1, Config.PRODUCT_PRICES[nextKey] or 0), true, function()
			MarketplaceService:PromptProductPurchase(player, Config.PRODUCTS[nextKey])
		end)
	elseif lv > 0 then
		section(nextOrder(), ("Luck Upgrade  %d / %d"):format(lv, Config.LUCK_LADDER.max), "Your area's rarest fish show up more often.")
	end

	-- a free boost for watching a video
	if Config.PRODUCTS.AD_BAIT ~= 0 then
		local r = section(nextOrder(), "Free Rare Boost", ("Watch a short video for %d minutes of Rare Boost."):format(Config.LUCK_BOOST_AD))
		local b = sideButton(r, "WATCH", true, function()
			act({ action = "watchAd" })
		end)
		b.Visible = false
		task.spawn(function()
			local ok, res = pcall(function()
				return game:GetService("AdService"):GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
			end)
			if ok and res and res.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable then
				b.Visible = true
			else
				local sub = r:FindFirstChild("Sub") :: TextLabel
				if sub then
					sub.Text = "No videos available right now. Check back later."
				end
			end
		end)
	end

	-- quest master
	local qs = profile.questStreak or { count = 0 }
	section(nextOrder(), "Quest Master", if profile.questMaster then "Unlocked! You have the Quest Master line." else ("Claim all your daily quests %d days in a row for the Quest Master line. Streak: %d / %d"):format(Config.QUEST_STREAK.days, math.min(qs.count or 0, Config.QUEST_STREAK.days), Config.QUEST_STREAK.days))
end

---------------------------------------------------------------- settings: codes and host controls

local function addSettingsRows()
	local se = Menus.windows.settings
	local ss = se and se:FindFirstChildWhichIsA("ScrollingFrame")
	if not ss then
		return
	end
	local base = 900
	Ui.label(ss, { LayoutOrder = base, Text = "CODES", Font = Ui.TITLE, TextSize = 15, TextColor3 = Ui.CYAN, Size = UDim2.new(1, -8, 0, 30), TextYAlignment = Enum.TextYAlignment.Bottom })
	local r = Ui.frame(ss, { LayoutOrder = base + 1, BackgroundTransparency = 0.5, BackgroundColor3 = Color3.fromRGB(30, 22, 70), Size = UDim2.new(1, -8, 0, 64) })
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = r
	local box = Instance.new("TextBox")
	box.PlaceholderText = "Enter a code"
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Font = Ui.TECH
	box.TextSize = 20
	box.TextColor3 = Ui.TEXT
	box.PlaceholderColor3 = Ui.MUTED
	box.BackgroundColor3 = Color3.fromRGB(18, 12, 44)
	box.Position = UDim2.fromOffset(14, 12)
	box.Size = UDim2.new(1, -200, 0, 40)
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 6)
	bc.Parent = box
	box.Parent = r
	local redeem = Ui.button(r, "REDEEM", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(160, 42) }, true)
	redeem.Activated:Connect(function()
		local res = request({ action = "code", code = box.Text })
		if res then
			toast(res.message or "", if res.ok then Ui.GOLD else Ui.RED)
			if res.ok then
				box.Text = ""
			end
		end
	end)

	-- private server host controls (only the owner sees them)
	local hostHead = Ui.label(ss, { LayoutOrder = base + 2, Text = "PRIVATE SERVER", Font = Ui.TITLE, TextSize = 15, TextColor3 = Ui.CYAN, Size = UDim2.new(1, -8, 0, 30), TextYAlignment = Enum.TextYAlignment.Bottom, Visible = false })
	local h = Ui.frame(ss, { LayoutOrder = base + 3, BackgroundTransparency = 0.5, BackgroundColor3 = Color3.fromRGB(30, 22, 70), Size = UDim2.new(1, -8, 0, 64), Visible = false })
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0, 6)
	hc.Parent = h
	local buttons = { { "METEORS", { action = "hostMeteor" } }, { "DAY", { action = "hostTime", time = "day" } }, { "DUSK", { action = "hostTime", time = "dusk" } }, { "NIGHT", { action = "hostTime", time = "night" } } }
	for i, b in buttons do
		local btn = Ui.button(h, b[1], { Position = UDim2.new((i - 1) / #buttons, 10, 0, 11), Size = UDim2.new(1 / #buttons, -16, 0, 42) }, i == 1)
		local t = btn:FindFirstChild("Text") :: TextLabel
		if t then
			t.TextSize = 15
		end
		btn.Activated:Connect(function()
			local res = request(b[2])
			if res then
				toast(res.message or "", if res.ok then Ui.GOLD else Ui.RED)
			end
		end)
	end
	Features._showHost = function(on: boolean)
		hostHead.Visible = on
		h.Visible = on
	end
end

---------------------------------------------------------------- in-world outlines

local outlines = {}
local function applyOutlines()
	for _, hl in outlines do
		hl:Destroy()
	end
	table.clear(outlines)
	if not Config.OUTLINES.enabled or Settings.get("lowGfx") then
		return
	end
	local world = workspace:FindFirstChild("World")
	if not world then
		return
	end
	local targets = {}
	for _, d in world:GetDescendants() do
		if d:IsA("Model") and table.find(Config.OUTLINES.names, d.Name) then
			if d.Name == "PassStands" then
				for _, m in d:GetChildren() do
					if m:IsA("Model") then
						table.insert(targets, m)
					end
				end
			else
				table.insert(targets, d)
			end
		end
	end
	for i, m in targets do
		if i > 24 then
			break -- (Roblox draws ~31 Highlights at once; leave room for fish auras)
		end
		local hl = Instance.new("Highlight")
		hl.Name = "ToonOutline"
		hl.FillTransparency = 1
		hl.OutlineColor = Config.OUTLINES.color
		hl.OutlineTransparency = 0.15
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Adornee = m
		hl.Parent = gui
		table.insert(outlines, hl)
	end
end

---------------------------------------------------------------- hooks from the main client script

function Features.onProfile(p)
	local prev = profile
	profile = p
	updateGoal()
	updateMarkers()
	if Features._showHost then
		Features._showHost(p.isHost == true)
	end
	-- the streak broke today: offer to restore it (once a session)
	if p.lostStreak and not lastOffer.STREAK_RESTORE then
		task.delay(4, function()
			offer("STREAK_RESTORE", ("Keep your %d-day streak?"):format(p.lostStreak), "You missed a day. Restore your daily streak and carry on where you left off.", 25, math.huge)
		end)
	end
	-- the bucket just filled up while fishing
	if fishing and #p.cargo >= p.cargoCap and (not prev or #prev.cargo < prev.cargoCap) then
		offer("BUCKET_PLUS", ("+%d bucket slots?"):format(Config.BUCKET_PLUS), "Your bucket is full. Keep fishing without walking back to Zorp (until you leave this server).", 15, 180)
	end
	if Menus and Menus.windows.workshop and Menus.windows.workshop.Visible then
		renderWorkshop()
	end
end

function Features.setFishing(on: boolean)
	fishing = on
	if not on then
		closeOffer()
	end
	updateGoal()
	updateMarkers()
end

-- a Rare/Epic got away: tell the server which one, then offer to keep it
function Features.onLost(index: number, def)
	if Config.PRODUCTS.KEEP_FISH == 0 then
		return
	end
	task.spawn(function()
		local ok, res = pcall(Remotes.Fish.InvokeServer, Remotes.Fish, { action = "lost", index = index })
		if ok and res and res.ok and res.offer then
			offer("KEEP_FISH", "Land the " .. def.name .. " anyway?", "It got away, but you can still catch it. It goes straight into your bucket.", Config.KEEP_FISH_SECONDS, 0)
		end
	end)
end

function Features.onMessage(msg)
	local kind = msg.kind
	if kind == "toast" then
		toast(msg.text or "", if msg.color == "green" then Ui.GOLD elseif msg.color == "red" then Ui.RED else Ui.CYAN)
	elseif kind == "meteorSoon" then
		if Settings.get("announce") ~= false then
			toast("A METEOR SHOWER starts in 2 minutes! Rare fish x2 for everyone", Ui.GOLD)
		end
	elseif kind == "meteor" then
		toast("METEOR SHOWER! Rare fish are biting twice as often", Ui.GOLD)
		Sounds.play("sparkle", { pitch = 0.7 })
	elseif kind == "pearl" then
		local f = Config.BY_ID[msg.id]
		toast(("A pearl inside your %s! +%s coins"):format(f and f.name or "fish", Ui.coinText(msg.coins or 0)), Ui.GOLD)
		Sounds.play("sparkle", { pitch = 1.3 })
	elseif kind == "secret" then
		toast("A strange signal is coming from The Void...", Color3.fromRGB(255, 205, 70))
		Sounds.play("sparkle", { pitch = 0.6 })
	elseif kind == "questMaster" then
		toast("QUEST MASTER! You unlocked the Quest Master line", Ui.GOLD)
	elseif kind == "kept" then
		Menus.showCatch(msg.caught or {})
	elseif kind == "sold" then
		offer("DOUBLE_SALE", ("Double it? +%s coins"):format(Ui.coinText(msg.total or 0)), "Get the same coins again for this sale.", Config.DOUBLE_SALE_SECONDS, 120)
	end
end

function Features.init(ctx)
	Menus = ctx.Menus
	gui = Ui.gui("Features", 7)
	meteorFolder.Parent = workspace
	meteorLabel = Ui.label(gui, { Text = "", Font = Ui.TITLE, TextSize = 20, TextColor3 = Ui.GOLD, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(620, 28), Visible = false })
	meteorLabel.TextStrokeTransparency = 0.3
	goalLabel = Ui.label(gui, { Text = "", Font = Ui.TECH, TextSize = 16, TextColor3 = Ui.CYAN, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -150), Size = UDim2.fromOffset(720, 22), Visible = false })
	goalLabel.TextStrokeTransparency = 0.3

	-- Zorp's Workshop: a side button and its window
	local w = Menus.newWindow("workshop", "Zorp's Workshop", Vector2.new(720, 640), function()
		renderWorkshop()
	end)
	local sc = Instance.new("ScrollingFrame")
	sc.BackgroundTransparency = 1
	sc.BorderSizePixel = 0
	sc.Position = UDim2.fromOffset(30, 80)
	sc.Size = UDim2.new(1, -60, 1, -100)
	sc.ScrollBarThickness = 4
	sc.ScrollBarImageColor3 = Ui.PURPLE
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sc.CanvasSize = UDim2.new()
	sc.ZIndex = 12
	sc.Parent = w
	workshopBody = sc
	if ctx.side then
		local b = Ui.iconButton(ctx.side, Art.icon.gift, "Workshop", { LayoutOrder = 6, Size = UDim2.fromOffset(90, 90) })
		b.Activated:Connect(function()
			Menus.open("workshop")
		end)
	end
	addSettingsRows()
	applyOutlines()
	Settings.onChanged(function(key)
		if key == "lowGfx" then
			applyOutlines()
		end
	end)

	task.spawn(function()
		while true do
			updateMeteor(serverNow())
			task.wait(0.25)
		end
	end)
	_ = RunService
end

return Features
