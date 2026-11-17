-- Fish in Space: client. HUD, docks, input, and the glue between the 2D fishing view,
-- the menus and the server.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("FishInSpace")
local Config = require(Shared:WaitForChild("Config"))
local Art = require(Shared:WaitForChild("Art"))
local Remotes = Shared:WaitForChild("Remotes")
local Ui = require(script:WaitForChild("Ui"))
local View = require(script:WaitForChild("FishingView"))
local Menus = require(script:WaitForChild("Menus"))
local Music = require(script:WaitForChild("Music"))
local Settings = require(script:WaitForChild("Settings"))
local Sounds = require(script:WaitForChild("Sounds"))
local Dialog = require(script:WaitForChild("Dialog"))
local Tutorial = require(script:WaitForChild("Tutorial"))
local Features = require(script:WaitForChild("Features")) -- the Nov 2026 features (workshop, meteor shower, offers, ...)

local player = Players.LocalPlayer
local profile = nil
local inZone = false
local zoneFacing = 0
local zonePart: BasePart? = nil
local fishing = false
local castToken = nil
local autoOn = false
local saved = { walk = 16, jump = 50 }

---------------------------------------------------------------- HUD

local hud = Ui.gui("Hud", 6)
-- two pills across the top: coins (with a green + that opens the Robux shop) and the bucket
local function pill(p: GuiObject)
	local c = p:FindFirstChildOfClass("UICorner")
	if c then
		c.CornerRadius = UDim.new(1, 0)
	end
end
local coinPanel = Ui.panel(hud, { Name = "Coins", Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(246, 62) })
pill(coinPanel)
Ui.image(coinPanel, Art.icon.coin, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), Size = UDim2.fromOffset(52, 52) })
local coinLabel = Ui.label(coinPanel, { Text = "0", Font = Ui.TITLE, TextSize = 30, TextColor3 = Ui.TEXT, Position = UDim2.fromOffset(64, 9), Size = UDim2.fromOffset(124, 42) })
local coinPlus = Ui.button(coinPanel, "+", { Name = "Plus", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, -2), Size = UDim2.fromOffset(42, 40) }, true)
local plusText = coinPlus:FindFirstChild("Text") :: TextLabel
plusText.TextSize = 34
coinPlus.Activated:Connect(function()
	Menus.openShopTab("robux")
end)
local cargoPanel = Ui.panel(hud, { Name = "BucketPill", Position = UDim2.fromOffset(270, 14), Size = UDim2.fromOffset(300, 62) })
pill(cargoPanel)
Ui.image(cargoPanel, Art.icon.cargo, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(50, 50) })
local cargoLabel = Ui.label(cargoPanel, { Text = "Bucket: 0 / 10", Font = Ui.TECH, TextSize = 20, Position = UDim2.fromOffset(64, 6), Size = UDim2.fromOffset(220, 24) })
local _, setCargo = Ui.meter(cargoPanel, 10, { Position = UDim2.fromOffset(64, 34), Size = UDim2.fromOffset(214, 14) }, Color3.fromRGB(90, 190, 255))
local luckLabel = Ui.label(hud, { Text = "", Font = Ui.TECH, TextSize = 17, TextColor3 = Ui.GOLD, Position = UDim2.fromOffset(20, 84), Size = UDim2.fromOffset(760, 22), Visible = false })

-- Zorp's fish quest (top right): which fish, caught or not, the reward, and unique fish caught
-- only shows while you have a quest from Zorp, and only that quest
local questPanel = Ui.panel(hud, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -84, 0, 18), Size = UDim2.fromOffset(340, 92), Visible = false })
local hasQuest = false
local questTitle = Ui.label(questPanel, { Text = "NO QUEST", Font = Ui.TITLE, TextSize = 17, TextColor3 = Ui.CYAN, Position = UDim2.fromOffset(18, 12), Size = UDim2.fromOffset(230, 22) })
local questStatus = Ui.label(questPanel, { Text = "", Font = Ui.TECH, TextSize = 15, Position = UDim2.fromOffset(18, 38), Size = UDim2.fromOffset(230, 20) })
local questReward = Ui.label(questPanel, { Text = "", Font = Ui.TECH, TextSize = 15, TextColor3 = Ui.GOLD, Position = UDim2.fromOffset(18, 60), Size = UDim2.fromOffset(230, 20) })
local uniqueLabel = Ui.label(questPanel, { Text = "", Font = Ui.TECH, TextSize = 14, TextColor3 = Ui.MUTED, Position = UDim2.fromOffset(18, 86), Size = UDim2.fromOffset(300, 18), Visible = false })
local questImage = Ui.image(questPanel, "", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(80, 40) })
local missingLabel = Ui.label(questPanel, { Text = "", Font = Ui.TECH, TextSize = 14, Position = UDim2.fromOffset(18, 108), Size = UDim2.fromOffset(310, 18), Visible = false })
local questFishView, questFishId = nil, nil
local function updateQuest(p)
	local q = p.fishQuest
	local found = 0
	local missing = nil
	for _, f in Config.FISH do
		if p.catalog and p.catalog[f.id] then
			found += 1
		elseif not missing then
			missing = f
		end
	end
	-- before Zorp's quests: a starter quest to catch a few different kinds of fish (shows once the tutorial is done)
	local need = Config.CAT_QUEST.minUnique
	local starter = not q and p.tutorialDone and not p.questsUnlocked
	hasQuest = (q ~= nil and Config.BY_ID[q.id] ~= nil) or starter
	if not hasQuest then
		questPanel.Visible = false
	else
		-- a new quest shows once Zorp has finished telling you about it
		Dialog.afterTalk(function()
			questPanel.Visible = hasQuest -- (shown while fishing too: it moves to the left then, see the HUD layout)
		end)
	end
	if q and Config.BY_ID[q.id] then
		local f = Config.BY_ID[q.id]
		local done = (q.have or 0) >= (q.need or 1)
		questTitle.Text = ("BRING %d %s"):format(q.need or 1, string.upper(f.name))
		questTitle.TextColor3 = Config.RARITY[f.rarity].color
		questStatus.Text = if done then "DONE! TALK TO ZORP" else ("%d / %d CAUGHT  ·  %s"):format(q.have or 0, q.need or 1, string.upper(f.rarity))
		questStatus.TextColor3 = if done then Ui.GREEN else Ui.TEXT
		questReward.Text = "REWARD: " .. Ui.coinText(q.reward) .. " COINS"
		questImage.Visible = false
		if questFishId ~= q.id then
			if questFishView then
				questFishView:Destroy()
			end
			questFishId = q.id
			questFishView = Ui.fish(questPanel, q.id, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(96, 52) })
		end
	else
		local done = found >= need
		questTitle.Text = ("CATCH %d KINDS OF FISH"):format(need)
		questTitle.TextColor3 = Ui.CYAN
		questStatus.Text = if done then "DONE! TALK TO ZORP" else ("%d / %d DIFFERENT FISH"):format(found, need)
		questStatus.TextColor3 = if done then Ui.GREEN else Ui.TEXT
		questReward.Text = "REWARD: ZORP'S QUESTS UNLOCK"
		questImage.Visible = false
		if questFishView then
			questFishView:Destroy()
			questFishView = nil
			questFishId = nil
		end
	end
	uniqueLabel.Text = ("UNIQUE FISH CAUGHT: %d / %d"):format(found, #Config.FISH)
	if missing then
		missingLabel.Text = "NOT CAUGHT YET: " .. string.upper(missing.name)
		missingLabel.TextColor3 = Config.RARITY[missing.rarity].color
	else
		missingLabel.Text = "EVERY FISH CAUGHT!  GOLDEN LINE UNLOCKED"
		missingLabel.TextColor3 = Ui.GOLD
	end
	View.setGoldLine(found >= #Config.FISH)
	View.setLineColor(Features.lineColor(p)) -- (God Rod, rebirth, Quest Master, crafted, VIP, Starter lines)
end

local side = Ui.frame(hud, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 18, 0.5, 40), Size = UDim2.fromOffset(92, 520) })
local sl = Instance.new("UIListLayout")
sl.Padding = UDim.new(0, 14)
sl.SortOrder = Enum.SortOrder.LayoutOrder
sl.Parent = side
local tiles = {}
for i, t in { { "robux", Art.icon.shop, "Shop" }, { "catalog", Art.icon.catalog, "Catalog" }, { "quests", Art.icon.quests, "Quests" }, { "cargo", Art.icon.cargo, "Bucket" }, { "rebirth", Art.icon.rebirth, "Rebirth" } } do
	local b = Ui.iconButton(side, t[2], t[3], { LayoutOrder = i, Size = UDim2.fromOffset(90, 90) })
	b.Activated:Connect(function()
		Menus.open(t[1])
	end)
	tiles[t[1]] = b
end
local questBadge = Ui.badge(tiles.quests)
local cargoBadge = Ui.badge(tiles.cargo)

local fishButton = Ui.button(hud, "START FISHING", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(300, 64), Visible = false }, true)
local fbText = fishButton:FindFirstChild("Text") :: TextLabel
fbText.TextSize = 24
local guide = Ui.label(hud, { Text = "", Font = Ui.TECH, TextSize = 19, TextColor3 = Ui.CYAN, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -116), Size = UDim2.fromOffset(700, 24) })

do
	local gs = Instance.new("UIStroke")
	gs.Thickness = 2
	gs.Transparency = 0.2
	gs.Color = Color3.fromRGB(8, 10, 24)
	gs.Parent = guide
end

local leaveButton = Ui.button(hud, "LEAVE", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 24), Size = UDim2.fromOffset(160, 48), Visible = false })
Ui.setStyle(leaveButton, "grey") -- (a neutral close-type button)
-- gear button (top right): opens Settings
local musicButton = Ui.iconButton(hud, Art.icon.settings, "", { Name = "SettingsButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 18), Size = UDim2.fromOffset(52, 52) })
musicButton.Activated:Connect(function()
	Menus.open("settings")
end)
local autoButton = Ui.button(hud, "AUTO: OFF", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 80), Size = UDim2.fromOffset(160, 48), Visible = false })

local relayoutHud: () -> () = function() end -- (set by the screen-fit code just below)
local autoPick: Frame -- (the Auto Fish rarity picker, made further down; placed by the layout)

---------------------------------------------------------------- fit the HUD to the screen
-- Everything on the HUD lives in one full-screen frame that is scaled down as a whole on small screens (phones),
-- so the layout keeps its shape instead of piling up. The top row sits beside Roblox's own top-bar buttons
-- (menu, chat, mic) when there is room, and below them when there isn't.
do
	local GuiService = game:GetService("GuiService")
	local hudRoot = Instance.new("Frame")
	hudRoot.Name = "Root"
	hudRoot.BackgroundTransparency = 1
	hudRoot.Size = UDim2.fromScale(1, 1)
	local hudScale = Instance.new("UIScale")
	hudScale.Parent = hudRoot
	for _, c in hud:GetChildren() do
		if c:IsA("GuiObject") then
			c.Parent = hudRoot
		end
	end
	hudRoot.Parent = hud
	hud.ChildAdded:Connect(function(c)
		if c ~= hudRoot and c:IsA("GuiObject") then
			task.defer(function()
				if c.Parent == hud then
					c.Parent = hudRoot
				end
			end)
		end
	end)
	local sideFit = Instance.new("UIScale")
	sideFit.Name = "Fit"
	sideFit.Parent = side
	local ROW_W = 246 + 8 + 300 -- coins + bucket pills
	local RIGHT_W = 340 + 80 -- quest card + settings button
	local function layout()
		local cam = workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(1280, 800)
		local s = math.clamp(math.min(vp.X / 1150, vp.Y / 720), 0.5, 1)
		hudScale.Scale = s
		hudRoot.Size = UDim2.fromScale(1 / s, 1 / s)
		local W, H = vp.X / s, vp.Y / s
		local inset = GuiService.TopbarInset
		local barTop, barH = inset.Min.Y / s, inset.Height / s
		local left = inset.Min.X / s
		local right = if inset.Max.X > 0 then math.min(W, inset.Max.X / s) else W
		local rowX, rowY
		if barH > 0 and left + 12 + ROW_W + 24 + RIGHT_W <= right then
			rowX, rowY = left + 12, math.max(6, barTop + (barH - 62) / 2) -- beside Roblox's buttons
		else
			rowX, rowY = 16, math.max(14, barTop + barH + 6) -- below them
		end
		coinPanel.Position = UDim2.fromOffset(rowX, rowY)
		cargoPanel.Position = UDim2.fromOffset(rowX + 254, rowY)
		luckLabel.Position = UDim2.fromOffset(rowX + 4, rowY + 70)
		musicButton.Position = UDim2.fromOffset(right - 18, rowY + 4)
		if fishing then
			-- while fishing the side buttons are hidden: the quest card sits on the left, under the pills
			questPanel.AnchorPoint = Vector2.new(0, 0)
			questPanel.Position = UDim2.fromOffset(rowX, rowY + 100)
		else
			questPanel.AnchorPoint = Vector2.new(1, 0)
			questPanel.Position = UDim2.fromOffset(right - 84, rowY + 4)
		end
		leaveButton.Position = UDim2.fromOffset(right - 24, rowY + 6)
		autoButton.Position = UDim2.fromOffset(right - 24, rowY + 62)
		if autoPick then
			autoPick.Position = UDim2.fromOffset(right - 24, rowY + 118) -- right under the Auto button
		end
		-- the side buttons: from under the top row to the bottom of the screen
		local rowBottom = rowY + 62 + 30 -- (room for the boost line under the pills)
		local avail = H - 24 - rowBottom
		-- one column if it fits; on short screens two columns, so the buttons stay big enough to tap (52px or more)
		local n = 0
		for _, c in side:GetChildren() do
			if c:IsA("GuiButton") and c.Visible then
				n += 1
			end
		end
		n = math.max(n, 1)
		local minFit = math.min(1, 52 / (90 * s))
		local cols = 1
		local fit = math.clamp(avail / (n * 104 - 14), minFit, 1)
		if (n * 104 - 14) * fit > avail + 1 then
			cols = 2
			fit = math.clamp(avail / (math.ceil(n / 2) * 104 - 14), minFit, 1)
		end
		local rows = math.ceil(n / cols)
		sl.Wraps = cols == 2
		sideFit.Scale = fit
		side.AnchorPoint = Vector2.new(0, 0)
		side.Size = UDim2.fromOffset(cols * 92 + (cols - 1) * 14, rows * 104 - 14)
		side.Position = UDim2.fromOffset(18, rowBottom + math.max(0, (avail - (rows * 104 - 14) * fit) / 2))
		hud:SetAttribute("SideRight", (18 + (cols * 92 + (cols - 1) * 14) * fit) * s)
		-- for other screens (the tutorial card sits under the top row)
		hud:SetAttribute("HudScale", s)
		hud:SetAttribute("TopBottom", (rowY + 62) * s)
	end
	relayoutHud = layout
	layout()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layout)
end

---------------------------------------------------------------- coins flying in
-- When you gain coins they burst out around you and fly into your character (or, in the fishing view, into the
-- coin counter), and the counter ticks up as each one arrives.
local shownCoins: number? = nil
local coinPop = Instance.new("UIScale")
coinPop.Parent = coinPanel
local coinSound = Instance.new("Sound")
coinSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
coinSound.Volume = 0.35
coinSound.Parent = hud
task.defer(function()
	coinSound.SoundGroup = game:GetService("SoundService"):FindFirstChild("SFX")
end)

-- a soft five-note scale (pentatonic), so a burst of coins sounds like a little wind chime
local CHIME = { 1, 1.122, 1.26, 1.498, 1.682 }
local function bumpCounter(value: number, k: number, last: boolean?)
	coinLabel.Text = Ui.coinText(value)
	coinPop.Scale = 1.12
	TweenService:Create(coinPop, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	-- one gentle chime for every few coins (and the last one), not a ping per coin
	if k % 3 == 1 or last then
		Sounds.play("coin", { pitch = CHIME[(math.floor((k - 1) / 3) % #CHIME) + 1] * (if last then 1.12 else 1), vary = 0.01 })
	end
end

local function bez(a: Vector3, b: Vector3, c: Vector3, t: number): Vector3
	return a:Lerp(b, t):Lerp(b:Lerp(c, t), t)
end

local function coinsToCharacter(n: number, onArrive: (number) -> ())
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	for i = 1, n do
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.CFrame = CFrame.new(origin)
		part.Parent = workspace
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromScale(1.6, 1.6)
		bb.LightInfluence = 0
		bb.Parent = part
		local img = Ui.image(bb, Art.ui.coin, { Size = UDim2.fromScale(1, 1) })
		-- burst out to a spot around you, then curve back in
		local a = math.random() * math.pi * 2
		local out = origin + Vector3.new(math.cos(a) * (4 + math.random() * 4), 2 + math.random() * 4, math.sin(a) * (4 + math.random() * 4))
		local delay = (i - 1) * 0.045
		task.delay(delay, function()
			local t0 = os.clock()
			local conn
			conn = RunService.RenderStepped:Connect(function()
				local t = os.clock() - t0
				local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local target = (r and r.Position or origin) + Vector3.new(0, 0.5, 0)
				if t < 0.28 then
					local u = 1 - (1 - t / 0.28) ^ 3 -- ease out
					part.Position = origin:Lerp(out, u)
				else
					local u = math.min(1, (t - 0.28) / 0.42)
					u = u * u -- ease in: speeds up into you
					part.Position = bez(out, out + Vector3.new(0, 3, 0), target, u)
					img.ImageTransparency = math.max(0, (u - 0.85) / 0.15)
					if u >= 1 then
						conn:Disconnect()
						part:Destroy()
						onArrive(i)
					end
				end
				img.Rotation = t * 400
			end)
		end)
	end
	return true
end

local function coinsToCounter(n: number, onArrive: (number) -> ())
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 800)
	local icon = coinPanel.AbsolutePosition + Vector2.new(38, 32)
	local layer = Ui.gui("CoinFly", 45)
	for i = 1, n do
		local img = Ui.image(layer, Art.ui.coin, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(34, 34) })
		local start = vp / 2 + Vector2.new(math.random(-140, 140), math.random(-90, 90))
		img.Position = UDim2.fromOffset(start.X, start.Y)
		task.delay((i - 1) * 0.05, function()
			local tw = TweenService:Create(img, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(icon.X, icon.Y), Size = UDim2.fromOffset(22, 22), Rotation = 360 })
			tw:Play()
			tw.Completed:Connect(function()
				img:Destroy()
				onArrive(i)
			end)
		end)
	end
	task.delay(n * 0.05 + 1.5, function()
		layer:Destroy()
	end)
end

local function showCoinGain(from: number, to: number)
	local gain = to - from
	local n = math.clamp(math.floor(gain / 5) + 3, 3, 16)
	local arrived = 0
	local function onArrive()
		arrived += 1
		local value = if arrived >= n then to else math.floor(from + gain * arrived / n)
		-- a newer gain may already be showing a higher number
		if shownCoins == to or value <= (shownCoins or value) then
			bumpCounter(value, arrived, arrived >= n)
		end
	end
	if fishing or not coinsToCharacter(n, onArrive) then
		coinsToCounter(n, onArrive)
	end
end

local function updateBadges()
	local q = Menus.questsReady()
	questBadge.Visible = q > 0
	questBadge.Text = tostring(q)
	if profile then
		local full = #profile.cargo >= profile.cargoCap
		cargoBadge.Visible = full
		cargoBadge.Text = "!"
	end
end
Menus.onBadges = updateBadges

-- the side buttons hide while fishing; Rebirth only shows once it's in sight (a quarter of the way to its cost)
-- or you've rebirthed before
local function updateSide()
	local rebirthShown = profile ~= nil
		and ((profile.rebirths or 0) > 0 or profile.coins >= 0.25 * (profile.rebirthCost or Config.rebirthCost(profile.rebirths or 0)))
	side.Visible = not fishing
	for name, b in tiles do
		b.Visible = name ~= "rebirth" or rebirthShown
	end
	relayoutHud()
end

local refreshAutoPick -- (the Auto Fish target picker, set up further down)
local function applyProfile(p)
	if not p then
		return
	end
	local firstLoad = profile == nil
	profile = p
	Settings.load(p.settings)
	if refreshAutoPick then
		refreshAutoPick()
	end
	if firstLoad and not p.tutorialDone then
		Tutorial.start({ menusOpen = Menus.anyOpen, openWindow = Menus.openWindow, ui = { fish = fishButton, leave = leaveButton, catalog = tiles.catalog, quests = tiles.quests, shop = tiles.robux } }) -- first time playing: show them how
	end
	if shownCoins ~= nil and p.coins > shownCoins then
		local from = shownCoins
		shownCoins = p.coins
		showCoinGain(from, p.coins) -- the counter ticks up as the coins arrive
	else
		shownCoins = p.coins
		coinLabel.Text = Ui.coinText(p.coins)
	end
	cargoLabel.Text = ("Bucket: %d / %d"):format(#p.cargo, p.cargoCap)
	setCargo(#p.cargo / p.cargoCap)
	autoButton.Visible = fishing and p.passes.AUTO_FISH
	Menus.setProfile(p)
	updateQuest(p)
	updateBadges()
	updateSide()
	Features.onProfile(p)
end

-- luck boost countdown
task.spawn(function()
	while true do
		task.wait(1)
		if profile then
			local now = (profile.now or 0) + (os.clock() - (profile._at or os.clock()))
			local left = (profile.luckUntil or 0) - now
			-- the Meteor Shower shares this line (under the coin and bucket pills), so it never covers anything
			local mUntil = workspace:GetAttribute("MeteorUntil") or 0
			local mNext = workspace:GetAttribute("MeteorNext") or 0
			local function clock(s)
				return ("%d:%02d"):format(math.floor(s / 60), math.floor(s % 60))
			end
			local parts = {}
			if now < mUntil then
				table.insert(parts, "METEOR SHOWER  " .. clock(mUntil - now) .. "  ·  RARE FISH x2")
			elseif mNext > now and mNext - now <= Config.METEOR.warn then
				table.insert(parts, "METEOR SHOWER IN " .. clock(mNext - now))
			end
			if left > 0 then
				-- what the boost does where you fish, e.g. "RARE BOOST 12:34 · EPICS 30% → 46%"
				table.insert(parts, ("RARE BOOST  %s  ·  %s"):format(clock(left), Config.boostText(Config.tierOf(profile.upgrades))))
			end
			luckLabel.Visible = #parts > 0
			luckLabel.Text = table.concat(parts, "     ")
			luckLabel.TextColor3 = if now < mUntil then Color3.fromRGB(255, 170, 90) else Ui.GOLD
		end
	end
end)

---------------------------------------------------------------- docks

local World = workspace:WaitForChild("World")
-- open space under the island in the lobby (the fishing view brings the sea surface back)
do
	local T = workspace.Terrain
	if T:GetAttribute("LobbyWaterTransparency") ~= nil then
		T.WaterTransparency = T:GetAttribute("LobbyWaterTransparency")
		T.WaterReflectance = T:GetAttribute("LobbyWaterReflectance")
		T.WaterWaveSize = T:GetAttribute("LobbyWaterWaveSize")
	end
end
local function checkZone()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	inZone = false
	if not root then
		return
	end
	-- the open edge of the island, or the pier
	local facing = Config.fishFacing(root.Position)
	if facing then
		inZone = true
		zoneFacing = facing
		zonePart = root
	end
end

-- walking speed, and sprinting (hold Shift; on phones a SPRINT button toggles it)
local WALK_SPEED, SPRINT_SPEED = 16, 28
local sprinting = false
local function setMovement(locked: boolean)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	if locked then
		saved.walk = if hum.WalkSpeed > 0 then hum.WalkSpeed else saved.walk
		saved.jump = if hum.JumpPower > 0 then hum.JumpPower else saved.jump
		hum.WalkSpeed = 0
		hum.JumpPower = 0
	else
		hum.WalkSpeed = if sprinting then SPRINT_SPEED else WALK_SPEED
		hum.JumpPower = saved.jump
	end
end

do
	local CAS = game:GetService("ContextActionService")
	local function apply()
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and not fishing then
			hum.WalkSpeed = if sprinting then SPRINT_SPEED else WALK_SPEED
		end
	end
	CAS:BindAction("Sprint", function(_, state, input)
		if input.UserInputType == Enum.UserInputType.Touch then
			-- the on-screen button toggles
			if state == Enum.UserInputState.Begin then
				sprinting = not sprinting
				CAS:SetTitle("Sprint", if sprinting then "WALK" else "SPRINT")
			end
		elseif state == Enum.UserInputState.Begin then
			sprinting = true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			sprinting = false
		end
		apply()
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)
	CAS:SetTitle("Sprint", "SPRINT")
	CAS:SetPosition("Sprint", UDim2.new(1, -175, 1, -95))
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Humanoid", 5)
		task.defer(apply)
	end)
end

local prefetchCast -- defined with the casting code below
local pendingCast = nil
local fetching = false

local function startFishing()
	if fishing or not inZone then
		return
	end
	fishing = true
	Menus.close()
	setMovement(true)
	-- face out to sea
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and zonePart then
		local out = (CFrame.Angles(0, math.rad(zoneFacing), 0) * CFrame.new(0, 0, -1)).Position
		local pos = root.Position
		-- step out to the end of the pier you're on, so you can start fishing from anywhere on the dock
		local pier = Config.fishPier(root.Position, 2)
		if pier then
			local spot = Config.fishSpot(pier)
			pos = Vector3.new(spot.X, pos.Y, spot.Z)
		end
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.lookAt(pos, pos + out)
	end
	fishButton.Visible = false
	updateSide()
	leaveButton.Visible = true
	questPanel.Visible = hasQuest -- (your quest stays on screen while you fish)
	autoButton.Visible = profile ~= nil and profile.passes.AUTO_FISH
	View.open({ character = player.Character, facing = zoneFacing })
	Tutorial.signal("fishStart")
	View.setAuto(autoOn)
	Music.setMode("sea")
	task.spawn(prefetchCast)
	musicButton.Visible = false
	guide.Text = ""
	Features.setFishing(true)
end

local function stopFishing()
	if not fishing then
		return
	end
	fishing = false
	if castToken then
		pcall(Remotes.Fish.InvokeServer, Remotes.Fish, { action = "cancel" })
		castToken = nil
	end
	pendingCast = nil
	View.close()
	setMovement(false)
	Tutorial.signal("fishStop")
	Music.setMode("island")
	musicButton.Visible = true
	updateSide()
	leaveButton.Visible = false
	questPanel.Visible = hasQuest
	autoButton.Visible = false
	Features.setFishing(false)
end

fishButton.Activated:Connect(startFishing)
leaveButton.Activated:Connect(stopFishing)
-- what Auto Fish goes after: a toggle per rarity under the Auto button (saved with your settings)
local AUTO_RARITIES = { "Common", "Uncommon", "Rare", "Epic" }
autoPick = Ui.frame(hud, { Name = "AutoTargets", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 136), Size = UDim2.fromOffset(160, 176), Visible = false })
Ui.label(autoPick, { Text = "AUTO CATCHES", Font = Ui.TECH, TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18) })
local autoChips = {}
local function autoSet(): { [string]: boolean }
	local set = {}
	for name in string.gmatch(Settings.get("autoTargets") or "", "[^,]+") do
		set[name] = true
	end
	return set
end
refreshAutoPick = function()
	local set = autoSet()
	local bait = if profile and profile.passes and profile.passes.GOD_ROD then 4 else Config.baitMax(profile and profile.upgrades.lure or 0)
	for name, b in autoChips do
		local on = set[name] == true
		local canBite = Config.RARITY[name].order <= bait
		Ui.setActive(b, on)
		local t = b:FindFirstChild("Text") :: TextLabel
		t.Text = string.upper(name) .. (if canBite then "" else "  · BAIT")
		t.TextColor3 = if not canBite then Ui.MUTED elseif on then Config.RARITY[name].color else Ui.TEXT
	end
	View.setAutoTargets(set)
end
for i, name in AUTO_RARITIES do
	local b = Ui.button(autoPick, string.upper(name), { Position = UDim2.fromOffset(0, 22 + (i - 1) * 38), Size = UDim2.fromOffset(160, 34) })
	local t = b:FindFirstChild("Text") :: TextLabel
	t.TextSize = 14
	b.Activated:Connect(function()
		local set = autoSet()
		set[name] = not set[name] or nil
		local list = {}
		for _, r in AUTO_RARITIES do
			if set[r] then
				table.insert(list, r)
			end
		end
		if #list == 0 then
			Menus.toast("Pick at least one kind of fish", Ui.RED)
			return
		end
		Settings.set("autoTargets", table.concat(list, ","))
	end)
	autoChips[name] = b
end
Settings.onChanged(function(key)
	if key == "autoTargets" then
		refreshAutoPick()
	end
end)
refreshAutoPick()

autoButton.Activated:Connect(function()
	autoOn = not autoOn
	Ui.setText(autoButton, if autoOn then "AUTO: ON" else "AUTO: OFF")
	Ui.setActive(autoButton, autoOn)
	View.setAuto(autoOn)
end)

---------------------------------------------------------------- casting

prefetchCast = function()
	if not fishing or pendingCast or fetching then
		return
	end
	fetching = true
	local ok, res = pcall(Remotes.Fish.InvokeServer, Remotes.Fish, { action = "start" })
	fetching = false
	if not fishing then
		if ok and res and res.ok then
			pcall(Remotes.Fish.InvokeServer, Remotes.Fish, { action = "cancel" })
		end
		return
	end
	if ok and res and res.ok then
		pendingCast = res
		castToken = res.token
		View.prepare(res)
	elseif ok and res and res.message then
		View.abort(res.message)
	end
end

local function requestCast(power: number)
	if pendingCast then
		local res = pendingCast
		pendingCast = nil
		castToken = res.token
		View.launch(res, power)
		return
	end
	local ok, res = pcall(Remotes.Fish.InvokeServer, Remotes.Fish, { action = "start" })
	if not fishing then
		return
	end
	if ok and res and res.ok then
		castToken = res.token
		View.launch(res, power)
	else
		local msg = if ok and res then res.message else "Try again"
		View.abort(msg)
		Menus.toast(msg or "", Ui.RED)
		if res and res.full then
			autoOn = false
			View.setAuto(false)
			Ui.setText(autoButton, "AUTO: OFF")
			Ui.setActive(autoButton, false)
		end
	end
end

local function autoCast()
	if not (fishing and autoOn) then
		return
	end
	if profile and #profile.cargo >= profile.cargoCap and profile.passes.AUTO_SELL then
		pcall(Remotes.Shop.InvokeServer, Remotes.Shop, { action = "sell" })
	end
	local p = View.autoCharge()
	if p then
		requestCast(p)
	end
end

View.init({
	onFinish = function(hooked)
		local token = castToken
		castToken = nil
		task.spawn(function()
			local ok, res = pcall(Remotes.Fish.InvokeServer, Remotes.Fish, { action = "finish", token = token, hooked = hooked })
			if ok and res and res.caught and #res.caught > 0 then
				Menus.showCatch(res.caught)
				Tutorial.signal("catch")
			end
			prefetchCast()
			task.wait(if autoOn then 1.4 else 0)
			autoCast()
		end)
	end,
	onState = function(s)
		Tutorial.signal("state", s)
	end,
	onLost = function(index, def)
		Features.onLost(index, def) -- (the "land it anyway" offer)
	end,
})

local function pressed(input: InputObject): boolean
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.ButtonA
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.F then
		if fishing then
			stopFishing()
		elseif inZone then
			startFishing()
		end
		return
	end
	if processed or not fishing or autoOn or Menus.anyOpen() then
		return
	end
	if pressed(input) then
		View.press()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not fishing or autoOn then
		return
	end
	if pressed(input) then
		local power = View.release()
		if power then
			requestCast(power)
		end
	end
end)

---------------------------------------------------------------- per frame

RunService.Heartbeat:Connect(function()
	checkZone()
	autoPick.Visible = autoButton.Visible
	if fishing then
		if not inZone then
			stopFishing()
		end
		if autoOn and View.state() == "aim" and (castToken == nil or (pendingCast ~= nil and castToken == pendingCast.token)) then
			autoCast()
		end
	else
		fishButton.Visible = inZone and not Menus.anyOpen()
		guide.Text = "" -- (new players get the full tutorial instead: FishClient.Tutorial)
	end
end)

player.CharacterAdded:Connect(function()
	stopFishing()
end)

---------------------------------------------------------------- server messages

Menus.init()
Features.init({ Menus = Menus, side = side, View = View })
Music.start()
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.M then
		local on = Settings.toggleMusic()
		Menus.toast(if on then "Music on" else "Music off", Ui.CYAN)
	end
end)
Remotes.State.OnClientEvent:Connect(function(msg)
	if typeof(msg) ~= "table" then
		return
	end
	if msg.type == "profile" then
		if msg.profile then
			msg.profile._at = os.clock()
		end
		applyProfile(msg.profile)
	elseif msg.type == "open" then
		if not fishing then
			Menus.open(msg.menu)
		end
	elseif msg.type == "talk" then
		Dialog.say(msg.who or "Zorp", msg.lines or {})
	elseif msg.type == "questFish" then
		local f = Config.BY_ID[msg.id]
		if (msg.have or 1) >= (msg.need or 1) then
			Sounds.play("sparkle")
			Menus.toast("Quest complete! Talk to Zorp", Ui.GREEN)
		else
			Menus.toast(("Quest fish: %s (%d / %d)"):format(f and f.name or "", msg.have or 0, msg.need or 1), Ui.GREEN)
		end
	elseif msg.type == "newQuest" then
		local f = Config.BY_ID[msg.id]
		Dialog.afterTalk(function()
			Menus.toast(("NEW QUEST: bring %d %s"):format(msg.need or 1, f and f.name or "fish"), Ui.CYAN)
		end)
	elseif msg.type == "allFish" and Settings.get("announce") then
		Menus.toast(msg.who .. " has caught EVERY fish!", Ui.GOLD)
	elseif msg.type == "sold" then
		local r = msg.result
		Menus.toast(r.message or "", if r.ok then Ui.GOLD else Ui.RED)
	elseif msg.type == "epic" and Settings.get("announce") then
		local f = Config.BY_ID[msg.id]
		local size = Config.SIZES[msg.size or 3]
		local col = f and Config.RARITY[f.rarity].color or Config.RARITY.Epic.color
		local name = f and f.name or "fish"
		local article = if size and (msg.size or 3) >= 4 then "a " .. string.upper(size.name) elseif name:match("^[AEIOUaeiou]") then "an" else "a"
		local text = ("%s caught %s %s!! (%s coins)"):format(msg.who, article, string.upper(name), Ui.coinText(msg.value or 0))
		Menus.toast(text, col)
		-- and a line in the chat, so the whole lobby sees it
		pcall(function()
			local channels = game:GetService("TextChatService"):FindFirstChild("TextChannels")
			local general = channels and channels:FindFirstChild("RBXGeneral")
			if general then
				local safe = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
				general:DisplaySystemMessage(('<font color="#%s"><b>%s</b></font>'):format(col:ToHex(), safe))
			end
		end)
	elseif msg.type == "streak" then
		Menus.showStreak(msg)
	elseif msg.type == "questReady" then
		Sounds.play("sparkle")
		Menus.toast("Quest complete: " .. msg.text, Ui.GREEN)
		Menus.refreshQuests()
	elseif msg.type == "feature" then
		Features.onMessage(msg)
	elseif msg.type == "rebirth" and msg.who == player.DisplayName then
		Features.onRebirth(msg) -- your own rebirth: the full-screen celebration
	elseif msg.type == "rebirth" and Settings.get("announce") then
		Menus.toast(("%s reached REBIRTH %d!"):format(msg.who, msg.n or 1), Ui.GOLD)
	elseif msg.type == "serverLuck" and Settings.get("announce") then
		Menus.toast(msg.who .. " started a SERVER RARE BOOST for everyone!", Ui.GOLD)
	end
end)

---------------------------------------------------------------- shop screens
-- The pass screens at the shop show their item in 3D, slowly turning. A 3D view only draws on a world screen when
-- that screen lives in PlayerGui (adorned to the part), so each screen is copied there and its item built here.
-- The screens can stream in and out, so this keeps checking.
do
	local views = {}
	local icons = Shared:WaitForChild("PassIcons", 10)
	local function fill(vf: ViewportFrame)
		if vf:GetAttribute("Filled") then
			return
		end
		local key = vf:GetAttribute("PassKey")
		local src = if key == "GOD_ROD" then Shared.Rods:FindFirstChild("GodRod") else icons and icons:FindFirstChild(key)
		if not src then
			return
		end
		vf:SetAttribute("Filled", true)
		local m = src:Clone()
		for _, d in m:GetDescendants() do
			if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("Highlight") then
				d:Destroy()
			end
		end
		local cf, size = m:GetBoundingBox()
		m:PivotTo(m:GetPivot() - cf.Position) -- centre it on the origin
		m.Parent = vf
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		local fit = math.max(size.X, size.Y, size.Z)
		cam.CFrame = CFrame.lookAt(Vector3.new(0, fit * 0.1, fit * 1.75), Vector3.zero)
		cam.Parent = vf
		vf.CurrentCamera = cam
		views[vf] = { model = m, base = m:GetPivot(), tilt = if key == "GOD_ROD" then 0.25 else 0 }
	end
	local mirrors = {} -- [world SurfaceGui] = copy in PlayerGui
	local function scan()
		for src, copy in mirrors do
			if not src.Parent or not copy.Adornee or not copy.Adornee.Parent then
				copy:Destroy()
				mirrors[src] = nil
			end
		end
		local pd = workspace:FindFirstChild("World") and workspace.World:FindFirstChild("Lobby") and workspace.World.Lobby:FindFirstChild("PassDisplays")
		if not pd then
			return
		end
		for _, sg in pd:GetDescendants() do
			if sg:IsA("SurfaceGui") and sg.Name == "ScreenGui" and not mirrors[sg] and sg.Parent:IsA("BasePart") then
				local copy = sg:Clone()
				copy.Name = "ShopScreen"
				copy.Adornee = sg.Parent
				copy.ResetOnSpawn = false
				copy.Enabled = true
				copy.Parent = player:WaitForChild("PlayerGui")
				sg.Enabled = false
				mirrors[sg] = copy
				for _, d in copy:GetDescendants() do
					if d:IsA("ViewportFrame") and d.Name == "ItemView" then
						d:SetAttribute("Filled", nil)
						fill(d)
					end
				end
			end
		end
	end
	task.spawn(function()
		while true do
			scan()
			task.wait(3)
		end
	end)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for vf, v in views do
			if vf.Parent then
				v.model:PivotTo(CFrame.Angles(0, t * 0.9, 0) * CFrame.Angles(0, 0, v.tilt) * v.base)
			else
				views[vf] = nil
			end
		end
	end)
end

---------------------------------------------------------------- tutorial hooks
Menus.opened.Event:Connect(function(name)
	Tutorial.signal("open", name)
end)
game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
	if prompt.Name == "ZorpPrompt" then
		Tutorial.signal("zorp")
	end
end)

---------------------------------------------------------------- Join the Group sign

-- a burst of coins and confetti from the sign
local function celebrate(at: BasePart)
	local att = Instance.new("Attachment")
	att.Parent = at
	att.WorldCFrame = CFrame.lookAt(at.Position, Vector3.new(0, at.Position.Y, 0)) -- toward the plaza
	local function burst(tex: string, colors: ColorSequence, n: number, size: number)
		local e = Instance.new("ParticleEmitter")
		e.Texture = tex
		e.Color = colors
		e.LightInfluence = 0
		e.Size = NumberSequence.new(size)
		e.Lifetime = NumberRange.new(1.4, 2.2)
		e.Speed = NumberRange.new(18, 30)
		e.SpreadAngle = Vector2.new(60, 60)
		e.EmissionDirection = Enum.NormalId.Front -- out of the sign's face, toward the plaza
		e.Acceleration = Vector3.new(0, -40, 0)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-240, 240)
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1) })
		e.Enabled = false
		e.Parent = att
		e:Emit(n)
	end
	burst(Art.ui.coin, ColorSequence.new(Color3.new(1, 1, 1)), 40, 1.1)
	burst("rbxasset://textures/particles/sparkles_main.dds", ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 110)),
		ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 205, 90)),
		ColorSequenceKeypoint.new(0.66, Color3.fromRGB(82, 242, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(161, 132, 255)),
	}), 70, 0.8)
	task.delay(3, function()
		att:Destroy()
	end)
end

game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
	if prompt.Name ~= "JoinGroupPrompt" then
		return
	end
	local gid = Config.GROUP and Config.GROUP.id or 0
	if gid == 0 then
		Menus.toast("The group isn't set up yet", Ui.RED)
		return
	end
	-- Roblox's own join window; then the server checks and gives the welcome coins once
	pcall(function()
		game:GetService("GroupService"):PromptJoinAsync(gid)
	end)
	local ok, res = pcall(Remotes.Shop.InvokeServer, Remotes.Shop, { action = "groupJoined" })
	if ok and res and res.ok and res.gift then
		Menus.toast(("Welcome to the group! +%s coins"):format(Ui.coinText(res.gift)), Ui.GOLD)
		local part = prompt.Parent
		if part and part:IsA("BasePart") then
			celebrate(part)
		end
	elseif ok and res and res.ok and res.already then
		Menus.toast("Thanks for being in the group!", Ui.CYAN)
	end
end)

task.spawn(function()
	local ok, res = pcall(Remotes.Shop.InvokeServer, Remotes.Shop, { action = "profile" })
	if ok and res and res.profile then
		res.profile._at = os.clock()
		applyProfile(res.profile)
	end
	Menus.refreshQuests()
end)
