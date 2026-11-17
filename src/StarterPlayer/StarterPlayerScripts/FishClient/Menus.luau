-- Fish in Space: menus (Upgrades, Robux Shop, Cosmic Catalog, Quests, Cargo, World 2, Settings) and pop-ups.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("FishInSpace")
local Config = require(Shared:WaitForChild("Config"))
local Art = require(Shared:WaitForChild("Art"))
local Remotes = Shared:WaitForChild("Remotes")
local Ui = require(script.Parent:WaitForChild("Ui"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local Settings = require(script.Parent:WaitForChild("Settings"))

local player = Players.LocalPlayer
local Menus = {}
Menus.opened = Instance.new("BindableEvent") -- fires with the window's name (the tutorial listens)

local gui: ScreenGui
local popGui: ScreenGui
local windows = {}
local profile = nil
local shopTab = "gear"
local catalogLayer = 1
local busy = false
local priceCache = {}
local toastList: Frame
local backdrop: TextButton

-- A darker inner fill so windows and cards read clearly over the bright world.
local function solid(w: GuiObject, inset: number?)
	-- the window body under its header: one even, slightly lighter area (the simulator look has no nested boxes)
	local i = inset or 12
	local f = Ui.frame(w, { Name = "Fill", BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(38, 28, 86), Position = UDim2.fromOffset(i, 76), Size = UDim2.new(1, -i * 2, 1, -76 - i), ZIndex = w.ZIndex })
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent = f
	return f
end

local function syncBackdrop()
	if not backdrop then
		return
	end
	local any = false
	for _, w in windows do
		if w.Visible then
			any = true
		end
	end
	backdrop.Visible = any
end

local function rarityColor(r: string): Color3
	return Config.RARITY[r].color
end

local function clear(f: Instance)
	for _, c in f:GetChildren() do
		if c:IsA("GuiObject") or c:IsA("UIGridStyleLayout") then
			c:Destroy()
		end
	end
end

local function robuxPrice(id: number, info: Enum.InfoType, cb: (string) -> ())
	if id == 0 then
		cb("SOON")
		return
	end
	local key = tostring(info) .. id
	if priceCache[key] then
		cb(priceCache[key])
		return
	end
	task.spawn(function()
		local ok, d = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, info)
		if ok and d and d.PriceInRobux then
			priceCache[key] = d.PriceInRobux .. " R$"
			cb(priceCache[key])
		end
	end)
end

---------------------------------------------------------------- toasts and pop-ups

-- Pop-up notices in the simulator style: a chunky coloured card with an icon.
--   green = good news (coins, sold, done), blue = info, red = a problem, purple = something rare / special
local TOAST = {
	green = { Color3.fromRGB(96, 214, 80), Color3.fromRGB(46, 160, 50), Art.icon.coin },
	blue = { Color3.fromRGB(80, 160, 255), Color3.fromRGB(40, 96, 220), Art.icon.fish },
	red = { Color3.fromRGB(255, 96, 100), Color3.fromRGB(196, 40, 56), Art.icon.lock },
	purple = { Color3.fromRGB(176, 110, 255), Color3.fromRGB(110, 56, 220), Art.icon.star },
}
function Menus.toast(text: string, color: Color3?)
	local kind = if color == Ui.GOLD or color == Ui.GREEN then "green" elseif color == Ui.RED then "red" elseif color == nil or color == Ui.CYAN or color == Ui.TEXT then "blue" else "purple"
	local T = TOAST[kind]
	local p = Instance.new("Frame")
	p.Name = "Toast"
	p.BorderSizePixel = 0
	p.BackgroundColor3 = Color3.new(1, 1, 1)
	p.Size = UDim2.fromOffset(420, 64)
	p.ZIndex = 60
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 16)
	c.Parent = p
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(T[1], T[2])
	g.Parent = p
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(1, 1, 1)
	st.Thickness = 3
	st.Transparency = 0.15
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = p
	local ic = Ui.image(p, T[3], { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(46, 46), ZIndex = 61 })
	local l = Ui.label(p, { Text = text, Font = Ui.TECH, TextSize = 20, TextWrapped = true, TextColor3 = Ui.TEXT, Position = UDim2.fromOffset(66, 4), Size = UDim2.new(1, -78, 1, -8), ZIndex = 61 })
	p.Parent = toastList
	Ui.pop(p)
	task.delay(3, function()
		local ti = TweenInfo.new(0.4)
		TweenService:Create(p, ti, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(st, ti, { Transparency = 1 }):Play()
		TweenService:Create(ic, ti, { ImageTransparency = 1 }):Play()
		TweenService:Create(l, ti, { TextTransparency = 1 }):Play()
		local ls = l:FindFirstChildOfClass("UIStroke")
		if ls then
			TweenService:Create(ls, ti, { Transparency = 1 }):Play()
		end
		task.wait(0.45)
		p:Destroy()
	end)
end

-- Small catch notices in the bottom-right corner: picture, name, rarity, coins (and a NEW tag for a
-- first catch). They stack, stay out of the way of the fishing view and fade on their own.
local catchList: Frame?
function Menus.showCatch(caught)
	local list = {}
	for _, c in caught do
		if not c.lost then
			table.insert(list, c)
		end
	end
	if #list == 0 then
		for _, c in caught do
			if c.lost then
				Menus.toast("Bucket full! A fish got away. Sell to Zorp.", Ui.RED)
				break
			end
		end
		return
	end
	if not catchList or not catchList.Parent then
		catchList = Ui.frame(popGui, { Name = "Catches", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -150), Size = UDim2.fromOffset(330, 360), ZIndex = 40 })
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 8)
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = catchList
	end
	for _, c in list do
		local f = Config.BY_ID[c.id]
		local col = rarityColor(f.rarity)
		local card = Ui.panel(catchList, { Size = UDim2.fromOffset(330, 66), LayoutOrder = math.floor(os.clock() * 100) % 1000000000, ZIndex = 40 })
		Ui.fish(card, f.id, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(88, 56), ZIndex = 41 })
		local sizeName = Config.SIZES[c.size].name
		Ui.label(card, { Text = string.upper((if sizeName ~= "Medium" then sizeName .. " " else "") .. f.name), Font = Ui.TITLE, TextSize = 13, TextScaled = false, TextWrapped = true, Position = UDim2.fromOffset(104, 7), Size = UDim2.fromOffset(168, 32), ZIndex = 41 })
		Ui.label(card, { Text = (if c.new then "NEW  ·  " else "") .. string.upper(f.rarity), Font = Ui.TECH, TextSize = 13, TextColor3 = if c.new then Ui.GOLD else col, AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.fromOffset(104, 41), Size = UDim2.fromOffset(0, 18), ZIndex = 41 })
		if (c.bonus or 0) > 0 then
			-- the depth bonus: deeper in an area = worth more
			Ui.label(card, { Text = ("+%d%% DEPTH"):format(c.bonus), Font = Ui.TECH, TextSize = 13, TextColor3 = Ui.CYAN, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 41), Size = UDim2.fromOffset(100, 18), ZIndex = 41 })
		end
		Ui.image(card, Art.ui.coin, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -54, 0.5, 0), Size = UDim2.fromOffset(18, 18), ZIndex = 41 })
		Ui.label(card, { Text = Ui.coinText(c.value), Font = Ui.TECH, TextSize = 15, TextColor3 = Ui.GOLD, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(40, 20), ZIndex = 41 })
		task.delay(2.8, function()
			if not card.Parent then
				return
			end
			TweenService:Create(card, TweenInfo.new(0.4), { ImageTransparency = 1 }):Play()
			for _, d in card:GetDescendants() do
				if d:IsA("TextLabel") then
					TweenService:Create(d, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
				elseif d:IsA("ImageLabel") or d:IsA("ViewportFrame") then
					TweenService:Create(d, TweenInfo.new(0.4), { ImageTransparency = 1 }):Play()
				end
			end
			task.wait(0.45)
			card:Destroy()
		end)
	end
end

---------------------------------------------------------------- windows

local render = {}

local function window(name: string, title: string, size: Vector2)
	local w = Ui.window(gui, title, size, function()
		Menus.close(name)
	end)
	solid(w, 12)
	windows[name] = w
	return w
end

-- other modules (FishClient.Features) add their own windows: same look, same open/close rules
Menus.windows = windows
function Menus.newWindow(name: string, title: string, size: Vector2, renderFn: (() -> ())?)
	local w = window(name, title, size)
	if renderFn then
		render[name] = renderFn
	end
	return w
end

function Menus.close(name: string?)
	for n, w in windows do
		if not name or n == name then
			w.Visible = false
		end
	end
	syncBackdrop()
end

function Menus.openWindow(): GuiObject?
	for _, w in windows do
		if w.Visible then
			return w
		end
	end
	return nil
end

function Menus.anyOpen(): boolean
	for _, w in windows do
		if w.Visible then
			return true
		end
	end
	return false
end


-- analytics: tell the server when the Robux Shop opens or a purchase prompt shows (the server checks and logs it)
local shopSource: string? = nil
local function analyticsSignal(kind: string, source: string?)
	local sig = Remotes:FindFirstChild("AnalyticsSignal")
	if sig then
		sig:FireServer(kind, source)
	end
end

-- "robux" opens the Robux-only Shop; anything else opens Upgrades
function Menus.openShopTab(tab: string)
	shopTab = tab
	local name = if tab == "robux" then "robux" else "shop"
	if not (windows[name] and windows[name].Visible) then
		if name == "robux" then
			shopSource = "Coin Plus" -- (only the + next to your coins opens the shop this way)
		end
		Menus.open(name)
	end
end

function Menus.open(name: string)
	local w = windows[name]
	if not w then
		return
	end
	local was = w.Visible
	Menus.close()
	if was then
		return
	end
	w.Visible = true
	syncBackdrop()
	Ui.pop(w)
	Sounds.play("open")
	Menus.opened:Fire(name)
	if name == "robux" then
		analyticsSignal("shopOpened", shopSource or "Side Button")
	end
	shopSource = nil
	if render[name] then
		render[name]()
	end
end

-- GEAR SHOP --------------------------------------------------------------------------------

local shopBody: Frame
local shopStatus: TextLabel
local shopTabs = {}

local function request(remote: RemoteFunction, req)
	if busy then
		return nil
	end
	busy = true
	local ok, res = pcall(remote.InvokeServer, remote, req)
	busy = false
	return if ok then res else nil
end

local lastUpgradeSound = 0 -- (one chime even when you buy many upgrades quickly; they used to stack)
local function gearRow(parent, order, key)
	local u = Config.UPGRADES[key]
	local level = profile.upgrades[key]
	local max = #u.costs
	local row = Ui.panel(parent, { Size = UDim2.new(1, 0, 0, 96), LayoutOrder = order, ZIndex = 12 })
	local iconFor = { tether = Art.icon.hook, hook = Art.icon.fish, cargo = Art.icon.cargo, lure = Art.icon.bait, reel = Art.icon.rod, throw = Art.icon.throw }
	local t = Ui.tile(row, iconFor[key], "", { Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(68, 68), ZIndex = 13 }, true)
	t.Active = false
	local name = u.name
	if key == "lure" then
		name = u.names[level + 1]
	end
	Ui.label(row, { Text = string.upper(name), Font = Ui.TITLE, TextSize = 17, Position = UDim2.fromOffset(98, 14), Size = UDim2.fromOffset(300, 22), ZIndex = 13 })
	local now = Config.upgradeValue(key, level)
	local nextV = if level < max then Config.upgradeValue(key, level + 1) else nil
	local function fmt(v)
		if key == "tether" then
			local depth = v + Config.CAST.rodTip.Y
			local name = Config.LAYERS[1].name
			for _, l in Config.LAYERS do
				if depth > l.from + 12 then
					name = l.name
				end
			end
			return math.floor(depth) .. "m deep · " .. (name:match("(%S+)$") or name)
		elseif key == "hook" then
			return v .. " fish"
		elseif key == "cargo" then
			return v .. " fish"
		elseif key == "lure" then
			return ({ "Common", "Uncommon", "Rare", "Epic" })[v] or "Common"
		elseif key == "throw" then
			-- the farthest layer this throw reaches (rarer fish live farther out)
			local lv = (table.find(u.values, v) or 1) - 1
			local name = Config.LAYERS[1].name
			for _, l in Config.LAYERS do
				if (l.throwLevel or 0) <= lv then
					name = l.name
				end
			end
			return math.floor(v / 4) .. " studs · " .. (name:match("(%S+)$") or name)
		end
		return v .. " reel"
	end
	Ui.label(row, { Text = u.desc, Font = Ui.BODY, TextSize = 15, TextColor3 = Ui.MUTED, Position = UDim2.fromOffset(98, 38), Size = UDim2.fromOffset(330, 18), ZIndex = 13 })
	Ui.label(row, { Text = if nextV then (fmt(now) .. "   →   " .. fmt(nextV)) else (fmt(now) .. "   ·   MAXED"), Font = Ui.TECH, TextSize = 16, TextColor3 = Ui.CYAN, Position = UDim2.fromOffset(98, 60), Size = UDim2.fromOffset(330, 20), ZIndex = 13 })
	-- level readout: long tracks get a 10-segment bar plus the exact level
	local _, setLv = Ui.meter(row, math.min(max, 10), { Position = UDim2.new(1, -236, 0, 16), Size = UDim2.fromOffset(110, 8), ZIndex = 13 })
	setLv(level / max)
	Ui.label(row, { Text = if level >= max then "MAX" else ("LV %d / %d"):format(level, max), Font = Ui.TECH, TextSize = 14, TextColor3 = if level >= max then Ui.GOLD else Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 10), Size = UDim2.fromOffset(100, 18), ZIndex = 13 })
	local cost = u.costs[level + 1]
	local b = Ui.button(row, if cost then Ui.coinText(cost) else "MAXED", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 6), Size = UDim2.fromOffset(170, 46), ZIndex = 13 }, cost ~= nil and profile.coins >= cost)
	if cost then
		Ui.image(b, Art.ui.coin, { Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(24, 12), ZIndex = 14 })
		b.Activated:Connect(function()
			local res = request(Remotes.Shop, { action = "upgrade", key = key })
			if res and res.ok then
				local now = os.clock()
				if now - lastUpgradeSound > 0.35 then
					lastUpgradeSound = now
					Sounds.play("sparkle", { volume = 0.8, pitch = 1.1 })
				end
			end
			if res then
				shopStatus.Text = string.upper(res.message or "")
				shopStatus.TextColor3 = if res.ok then Ui.GREEN else Ui.RED
			end
		end)
	end
end

local function robuxCard(parent, order, icon, title, desc, id, info, owned)
	local card = Ui.panel(parent, { Size = UDim2.fromOffset(196, 214), LayoutOrder = order, ZIndex = 12 }, owned)
	Ui.image(card, icon, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(78, 78), ZIndex = 13 })
	Ui.label(card, { Text = string.upper(title), Font = Ui.TITLE, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(8, 78), Size = UDim2.new(1, -16, 0, 20), ZIndex = 13 })
	Ui.label(card, { Text = desc, Font = Ui.BODY, TextSize = 13, TextColor3 = Ui.MUTED, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(14, 100), Size = UDim2.new(1, -28, 0, 54), ZIndex = 13 })
	local b = Ui.button(card, if owned then "OWNED" else "...", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(160, 42), ZIndex = 13 }, not owned)
	if not owned then
		robuxPrice(id, info, function(p)
			Ui.setText(b, p)
		end)
		b.Activated:Connect(function()
			if id == 0 then
				Menus.toast("Coming soon!", Ui.CYAN)
			elseif info == Enum.InfoType.GamePass then
				analyticsSignal("promptShown")
				MarketplaceService:PromptGamePassPurchase(player, id)
			else
				analyticsSignal("promptShown")
				MarketplaceService:PromptProductPurchase(player, id)
			end
		end)
	end
end

-- the free card: join the official group for a coin bonus
local function groupCard(parent, order)
	local member = player:GetAttribute("InGroup") == true
	local pct = math.floor(Config.GROUP_COIN_BONUS * 100 + 0.5)
	local card = Ui.panel(parent, { Size = UDim2.fromOffset(196, 214), LayoutOrder = order, ZIndex = 12 }, member)
	Ui.image(card, Art.icon.gift, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(78, 78), ZIndex = 13 })
	Ui.label(card, { Text = "JOIN THE GROUP", Font = Ui.TITLE, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(8, 78), Size = UDim2.new(1, -16, 0, 20), ZIndex = 13 })
	Ui.label(card, { Text = ("FREE! Group members sell every fish for +%d%% coins."):format(pct), Font = Ui.BODY, TextSize = 13, TextColor3 = Ui.MUTED, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(14, 100), Size = UDim2.new(1, -28, 0, 54), ZIndex = 13 })
	local b = Ui.button(card, if member then ("+%d%% ACTIVE"):format(pct) else "JOIN", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(160, 42), ZIndex = 13 }, not member)
	if member then
		return
	end
	b.Activated:Connect(function()
		local ok = pcall(function()
			game:GetService("GroupService"):PromptJoinAsync(Config.GROUP_ID)
		end)
		if not ok then
			Menus.toast("Search \"Fish in Space\" in Groups to join!", Ui.CYAN)
		end
		-- ask the server to check again (it re-renders the shop with the bonus on)
		local res = request(Remotes.Shop, { action = "groupCheck" })
		if res and res.ok then
			Menus.toast(res.message, Ui.GREEN)
			Sounds.play("sparkle", { volume = 0.8, pitch = 1.1 })
		end
	end)
end

local robuxBody: Frame
local function renderStore(kind: string)
	if not profile then
		return
	end
	local shopBody = if kind == "gear" then shopBody else robuxBody
	clear(shopBody)
	if kind == "gear" then
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 10)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = shopBody
		-- NEXT AREA: the first area you can't reach yet, and which upgrades it still needs
		local nextLi
		for li = 2, #Config.LAYERS do
			local n = Config.areaNeeds(li)
			if profile.upgrades.tether < n.tether or (profile.upgrades.throw or 0) < n.throw or profile.upgrades.lure < n.lure then
				nextLi = li
				break
			end
		end
		local goal = Ui.panel(shopBody, { Size = UDim2.new(1, 0, 0, 78), LayoutOrder = 0, ZIndex = 12 }, true)
		if nextLi then
			local L = Config.LAYERS[nextLi]
			local n = Config.areaNeeds(nextLi)
			Ui.label(goal, { Text = "NEXT AREA:  " .. string.upper(L.name) .. "   ·   YOU NEED",  Font = Ui.TITLE, TextSize = 16, TextColor3 = Config.RARITY[Config.TOP_RARITY[nextLi]].color, Position = UDim2.fromOffset(22, 12), Size = UDim2.new(1, -44, 0, 20), ZIndex = 13 })
			local chips = Ui.frame(goal, { Position = UDim2.fromOffset(22, 40), Size = UDim2.new(1, -44, 0, 24), ZIndex = 13 })
			local cl = Instance.new("UIListLayout")
			cl.FillDirection = Enum.FillDirection.Horizontal
			cl.Padding = UDim.new(0, 18)
			cl.Parent = chips
			for i, req in {
				{ "LINE LENGTH LV " .. n.tether, profile.upgrades.tether >= n.tether },
				{ "DISTANCE THROW LV " .. n.throw, (profile.upgrades.throw or 0) >= n.throw },
				{ string.upper(Config.UPGRADES.lure.names[n.lure + 1]), profile.upgrades.lure >= n.lure },
			} do
				-- (the game's fonts have no tick/cross symbols: done ones say so in green, the rest stay bright)
				Ui.label(chips, { Text = req[1] .. (if req[2] then "  DONE" else ""), Font = Ui.TECH, TextSize = 15, TextColor3 = if req[2] then Ui.GREEN else Ui.TEXT, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = i, ZIndex = 13 })
			end
		else
			Ui.label(goal, { Text = "EVERY AREA UNLOCKED", Font = Ui.TITLE, TextSize = 16, TextColor3 = Ui.GOLD, Position = UDim2.fromOffset(22, 14), Size = UDim2.new(1, -44, 0, 20), ZIndex = 13 })
			Ui.label(goal, { Text = "Keep upgrading to fish faster and carry more.", Font = Ui.BODY, TextSize = 15, TextColor3 = Ui.MUTED, Position = UDim2.fromOffset(22, 42), Size = UDim2.new(1, -44, 0, 20), ZIndex = 13 })
		end
		for i, key in Config.UPGRADE_ORDER do
			gearRow(shopBody, i, key)
		end
	else
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(1 / 3, -12, 0, 214)
		grid.CellPadding = UDim2.fromOffset(12, 14)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = shopBody
		local pp = profile.passes
		local GP, PR = Enum.InfoType.GamePass, Enum.InfoType.Product
		local up = profile.upgrades
		local order = 0
		local function card(icon, title, desc, id, info, owned)
			order += 1
			robuxCard(shopBody, order, icon, title, desc, id, info, owned)
		end
		-- the Starter Pack, only during your first hour
		if (profile.starterLeft or 0) > 0 then
			card(Art.icon.star, "Starter Pack", ("Rare Boost, +%s coins and a green Starter line. One time only!"):format(Ui.coinText(Config.coinPack("COINS_MEDIUM", up))), Config.PRODUCTS.STARTER_PACK, PR, false)
		end
		-- the free group bonus
		order += 1
		groupCard(shopBody, order)
		-- passes: buy once, keep forever
		card(Art.icon.coin, "2x Coins", "Every fish sells for double.", Config.PASSES.DOUBLE_COINS, GP, pp.DOUBLE_COINS)
		card(Art.icon.fish, "+1 Hook", "Catch two fish on one cast.", Config.PASSES.PLUS_HOOK, GP, pp.PLUS_HOOK)
		card(Art.icon.auto, "Auto Fish", "Casts and reels for you. Stops when your bucket is full (unless you have Auto-Sell).", Config.PASSES.AUTO_FISH, GP, pp.AUTO_FISH)
		card(Art.icon.sell, "Auto-Sell", "Sell the fish in your bucket from anywhere.", Config.PASSES.AUTO_SELL, GP, pp.AUTO_SELL)
		card(Art.icon.cargo, "Bigger Bucket", "+50% bucket space on top of your upgrades.", Config.PASSES.BIG_BUCKET, GP, pp.BIG_BUCKET)
		card(Art.icon.crown, "VIP", "+20% sell price, a bigger daily reward, a VIP aura and a cyan line.", Config.PASSES.VIP, GP, pp.VIP)
		card(Art.icon.rod, "God Rod", "Fish worth +50%, every rarity bites, 1.5x faster reel and sink, an aura and a magenta line.", Config.PASSES.GOD_ROD, GP, pp.GOD_ROD)
		-- products: buy as often as you like
		local boost = Config.boostText(Config.tierOf(up))
		card(Art.icon.luck, "Rare Boost", ("Rarer fish for you for 15 minutes. Here: %s."):format(boost), Config.PRODUCTS.LUCKY_LURE, PR, false)
		card(Art.icon.luck, "Server Rare Boost", "Rarer fish for EVERYONE in the server for 15 minutes.", Config.PRODUCTS.SERVER_LUCK, PR, false)
		card(Art.ui.coin, "Coin Pouch", "+" .. Ui.coinText(Config.coinPack("COINS_SMALL", up)) .. " coins. Grows as you go deeper.", Config.PRODUCTS.COINS_SMALL, PR, false)
		card(Art.ui.coin, "Coin Sack", "+" .. Ui.coinText(Config.coinPack("COINS_MEDIUM", up)) .. " coins. Grows as you go deeper.", Config.PRODUCTS.COINS_MEDIUM, PR, false)
		card(Art.ui.coin, "Coin Chest", "+" .. Ui.coinText(Config.coinPack("COINS_LARGE", up)) .. " coins. Best value!", Config.PRODUCTS.COINS_LARGE, PR, false)
	end
end
render.shop = function()
	renderStore("gear")
end
render.robux = function()
	renderStore("robux")
end

-- COSMIC CATALOG ------------------------------------------------------------------------

local catBody: Frame
local catTabs = {}
local catDone: TextLabel
local setCatDone: (number) -> ()

render.catalog = function()
	if not profile then
		return
	end
	local total, found = 0, 0
	for _, f in Config.FISH do
		total += 1
		if profile.catalog[f.id] then
			found += 1
		end
	end
	catDone.Text = ("%d / %d DISCOVERED"):format(found, total)
	setCatDone(found / total)
	for i, b in catTabs do
		Ui.setActive(b, i == catalogLayer)
	end
	clear(catBody)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.25, -10, 0, 176)
	grid.CellPadding = UDim2.fromOffset(12, 12)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = catBody
	local order = 0
	-- holiday fish (in season, or once caught) and the secret fish (once caught) join the end of their area's page;
	-- they don't count toward the total, so nobody needs them for 100%
	local list = table.clone(Config.FISH)
	for _, sf in Config.SPECIAL_FISH do
		local season = sf ~= Config.SECRET_FISH and Config.holidayOpen(sf)
		if profile.catalog[sf.id] or season then
			table.insert(list, sf)
		end
	end
	for _, f in list do
		if f.layer == catalogLayer then
			order += 1
			local e = profile.catalog[f.id]
			local col = rarityColor(f.rarity)
			local holding = profile.held == f.id
			local card = Ui.panel(catBody, { Size = UDim2.fromOffset(196, 176), LayoutOrder = order, ZIndex = 12 }, holding)
			local img = Ui.fish(card, f.id, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(170, 82), ZIndex = 13 })
			if not e then
				-- not caught yet: a dark purple silhouette
				img.ImageColor3 = Color3.fromRGB(70, 55, 120)
				img.ImageTransparency = 0.15
				if img:IsA("ViewportFrame") then
					img.Ambient = Color3.new(1, 1, 1)
					img.LightColor = Color3.new(0, 0, 0)
					for _, pt in img:GetDescendants() do
						if pt:IsA("BasePart") then
							pt.Color = Color3.new(1, 1, 1)
							pt.Material = Enum.Material.SmoothPlastic
						end
					end
				end
			end
			Ui.label(card, { Text = if e then string.upper(f.name) else "???", Font = Ui.TITLE, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(6, 90), Size = UDim2.new(1, -12, 0, 18), ZIndex = 13 })
			Ui.label(card, { Text = string.upper(f.rarity) .. (if e then "  ·  BEST " .. string.upper(Config.SIZES[e.best].name) else ""), Font = Ui.TECH, TextSize = 14, TextColor3 = col, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(6, 108), Size = UDim2.new(1, -12, 0, 16), ZIndex = 13 })
			if e then
				local b = Ui.button(card, if holding then "PUT AWAY" else "HOLD", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(150, 36), ZIndex = 13 }, holding)
				b.Activated:Connect(function()
					local res = request(Remotes.Catalog, { action = "hold", id = f.id })
					if res and res.ok then
						profile.held = res.holding
						render.catalog()
					elseif res then
						Menus.toast(res.message or "", Ui.RED)
					end
				end)
			else
				Ui.label(card, { Text = "NOT CAUGHT YET", Font = Ui.TECH, TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(1, 0, 0, 16), ZIndex = 13 })
			end
		end
	end
end

-- QUESTS --------------------------------------------------------------------------------

local questBody: Frame
local questFoot: TextLabel
local readyCount = 0
local lastQuestData = nil
local function zorpDone(): boolean
	local q = profile and profile.fishQuest
	return q ~= nil and (q.have or 0) >= (q.need or 1)
end
function Menus.questsReady(): number
	-- daily quests to claim, plus a finished Zorp quest waiting to be turned in
	return readyCount + (if zorpDone() then 1 else 0)
end

-- Zorp's fish quest, from the profile: what he wants, how far along you are, and what to do next
local function zorpRow(order: number)
	Ui.label(questBody, { Text = "ZORP'S QUEST", Font = Ui.TECH, TextSize = 15, TextColor3 = Ui.CYAN, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order, ZIndex = 12 })
	local q = profile and profile.fishQuest
	local f = q and Config.BY_ID[q.id]
	local done = zorpDone()
	local row = Ui.panel(questBody, { Size = UDim2.new(1, 0, 0, 84), LayoutOrder = order + 1, ZIndex = 12 }, done)
	if f then
		Ui.fish(row, f.id, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(96, 56), ZIndex = 13 })
		Ui.label(row, { Text = ("BRING %d %s"):format(q.need or 1, string.upper(f.name)), Font = Ui.TECH, TextSize = 17, TextColor3 = rarityColor(f.rarity), Position = UDim2.fromOffset(122, 10), Size = UDim2.new(1, -340, 0, 22), ZIndex = 13 })
		local _, set = Ui.meter(row, math.max(1, q.need or 1), { Position = UDim2.fromOffset(122, 38), Size = UDim2.new(1, -350, 0, 10), ZIndex = 13 }, if done then Ui.GREEN else Ui.CYAN)
		set((q.have or 0) / (q.need or 1))
		Ui.label(row, { Text = if done then "Done! Talk to Zorp at any dock to collect." else ("Catch them (%s), then talk to Zorp at any dock."):format(f.rarity), Font = Ui.BODY, TextSize = 14, TextColor3 = if done then Ui.GREEN else Ui.MUTED, Position = UDim2.fromOffset(122, 54), Size = UDim2.new(1, -340, 0, 20), ZIndex = 13 })
		Ui.label(row, { Text = ("%d / %d     +%s COINS"):format(q.have or 0, q.need or 1, Ui.coinText(q.reward or 0)), Font = Ui.TECH, TextSize = 16, TextColor3 = Ui.GOLD, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(200, 22), ZIndex = 13 })
	else
		-- no quest yet: either talk to him, or catch a few more kinds of fish first
		local unique = 0
		for _, ff in Config.FISH do
			if profile and profile.catalog and profile.catalog[ff.id] then
				unique += 1
			end
		end
		local need = Config.CAT_QUEST.minUnique
		local text = if unique < need then ("Catch %d different kinds of fish to unlock Zorp's quests (%d / %d)."):format(need, unique, need) else "Talk to Zorp at any dock for a fish quest."
		Ui.label(row, { Text = text, Font = Ui.TECH, TextSize = 16, TextWrapped = true, Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -40, 1, 0), ZIndex = 13 })
	end
end

local function questRows(data)
	lastQuestData = data
	clear(questBody)
	readyCount = 0
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = questBody
	zorpRow(1)
	local order = 2
	for _, group in { { "DAILY", data.daily } } do
		order += 1
		Ui.label(questBody, { Text = group[1], Font = Ui.TECH, TextSize = 15, TextColor3 = Ui.CYAN, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order, ZIndex = 12 })
		for _, q in group[2] do
			order += 1
			local ready = q.progress >= q.goal and not q.claimed
			if ready then
				readyCount += 1
			end
			local row = Ui.panel(questBody, { Size = UDim2.new(1, 0, 0, 70), LayoutOrder = order, ZIndex = 12 }, ready)
			Ui.label(row, { Text = q.text, Font = Ui.TECH, TextSize = 17, Position = UDim2.fromOffset(20, 10), Size = UDim2.new(1, -220, 0, 22), ZIndex = 13 })
			local _, set = Ui.meter(row, 10, { Position = UDim2.fromOffset(20, 40), Size = UDim2.new(1, -230, 0, 10), ZIndex = 13 }, if q.claimed then Ui.GREEN else Ui.CYAN)
			set(q.progress / q.goal)
			local right = UDim2.new(1, -16, 0.5, 0)
			if ready then
				local b = Ui.button(row, "CLAIM " .. Ui.coinText(q.coins), { AnchorPoint = Vector2.new(1, 0.5), Position = right, Size = UDim2.fromOffset(180, 44), ZIndex = 13 }, true)
				b.Activated:Connect(function()
					local res = request(Remotes.Quest, { action = "claim", id = q.id })
					if res and res.ok then
						Menus.toast(("+%s coins"):format(Ui.coinText(res.coins)), Ui.GOLD)
						questRows(res)
					end
				end)
			else
				Ui.label(row, { Text = if q.claimed then "CLAIMED" else ("%d / %d     +%s COINS"):format(q.progress, q.goal, Ui.coinText(q.coins)), Font = Ui.TECH, TextSize = 16, TextColor3 = if q.claimed then Ui.GREEN else Ui.GOLD, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5), Position = right, Size = UDim2.fromOffset(200, 22), ZIndex = 13 })
			end
		end
	end
	if data.dailyResetIn then
		local h = math.floor(data.dailyResetIn / 3600)
		local m = math.floor((data.dailyResetIn % 3600) / 60)
		questFoot.Text = ("DAILY QUESTS RESET IN %dH %02dM"):format(h, m)
	end
	if Menus.onBadges then
		Menus.onBadges()
	end
end

render.quests = function()
	task.spawn(function()
		local ok, data = pcall(Remotes.Quest.InvokeServer, Remotes.Quest, { action = "list" })
		if ok and data then
			questRows(data)
		end
	end)
end
Menus.refreshQuests = render.quests

-- REBIRTH --------------------------------------------------------------------------------

local rebirthBody: ScrollingFrame
local rebirthStatus: TextLabel
local rebirthConfirm = 0
render.rebirth = function()
	if not profile then
		return
	end
	clear(rebirthBody)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = rebirthBody
	local R = Config.REBIRTH
	local n = profile.rebirths or 0
	local cost = profile.rebirthCost or Config.rebirthCost(n)
	local voidOk = Config.tierOf(profile.upgrades) >= R.needTier
	local coinsOk = profile.coins >= cost
	-- the rebirth itself
	local top = Ui.panel(rebirthBody, { Size = UDim2.new(1, -8, 0, 214), LayoutOrder = 1, ZIndex = 12 }, true)
	Ui.label(top, { Text = if n > 0 then ("REBIRTH %d"):format(n) else "NO REBIRTHS YET", Font = Ui.TITLE, TextSize = 22, TextColor3 = Ui.GOLD, Position = UDim2.fromOffset(24, 16), Size = UDim2.new(1, -48, 0, 28), ZIndex = 13 })
	Ui.label(top, { Text = ("COINS  x%.2f  →  x%.2f  FOREVER  ·  +1 PERK TOKEN"):format(Config.coinMult(n), Config.coinMult(n + 1)), Font = Ui.TECH, TextSize = 17, TextColor3 = Ui.CYAN, Position = UDim2.fromOffset(24, 50), Size = UDim2.new(1, -48, 0, 22), ZIndex = 13 })
	local chips = Ui.frame(top, { Position = UDim2.fromOffset(24, 80), Size = UDim2.new(1, -48, 0, 22), ZIndex = 13 })
	local cl = Instance.new("UIListLayout")
	cl.FillDirection = Enum.FillDirection.Horizontal
	cl.Padding = UDim.new(0, 22)
	cl.Parent = chips
	for i, req in { { "UNLOCK THE VOID", voidOk }, { ("%s / %s COINS"):format(Ui.coinText(math.min(profile.coins, cost)), Ui.coinText(cost)), coinsOk } } do
		Ui.label(chips, { Text = req[1] .. (if req[2] then "  DONE" else ""), Font = Ui.TECH, TextSize = 15, TextColor3 = if req[2] then Ui.GREEN else Ui.TEXT, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = i, ZIndex = 13 })
	end
	Ui.label(top, { Text = "Resets your coins, upgrades and bucket. Keeps your catalog, stats, quests, passes and perks.", Font = Ui.BODY, TextSize = 15, TextColor3 = Ui.MUTED, TextWrapped = true, Position = UDim2.fromOffset(24, 108), Size = UDim2.new(1, -48, 0, 36), ZIndex = 13 })
	local ready = voidOk and coinsOk
	local b = Ui.button(top, if ready then "REBIRTH" else "NOT YET", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(300, 50), ZIndex = 13 }, ready)
	b.Activated:Connect(function()
		if not ready then
			rebirthStatus.Text = if not voidOk then "UNLOCK THE VOID FIRST" else ("NEED %s MORE COINS"):format(Ui.coinText(cost - profile.coins))
			rebirthStatus.TextColor3 = Ui.RED
			return
		end
		-- two taps, so nobody resets by accident
		if os.clock() - rebirthConfirm > 3 then
			rebirthConfirm = os.clock()
			Ui.setText(b, "TAP AGAIN TO CONFIRM")
			return
		end
		rebirthConfirm = 0
		local res = request(Remotes.Shop, { action = "rebirth" })
		if res then
			rebirthStatus.Text = string.upper(res.message or "")
			rebirthStatus.TextColor3 = if res.ok then Ui.GOLD else Ui.RED
			if res.ok then
				Sounds.play("sparkle", { pitch = 0.8 })
			end
		end
	end)
	-- perks
	Ui.label(rebirthBody, { Text = ("PERKS  ·  %d TOKEN%s TO SPEND"):format(profile.tokens or 0, if (profile.tokens or 0) == 1 then "" else "S"), Font = Ui.TECH, TextSize = 15, TextColor3 = Ui.CYAN, Size = UDim2.new(1, -8, 0, 22), LayoutOrder = 2, ZIndex = 12 })
	for i, pk in R.perks do
		local lv = (profile.perks and profile.perks[pk.key]) or 0
		local row = Ui.panel(rebirthBody, { Size = UDim2.new(1, -8, 0, 88), LayoutOrder = 2 + i, ZIndex = 12 })
		Ui.label(row, { Text = string.upper(pk.name), Font = Ui.TITLE, TextSize = 16, Position = UDim2.fromOffset(22, 12), Size = UDim2.new(1, -240, 0, 22), ZIndex = 13 })
		Ui.label(row, { Text = pk.desc, Font = Ui.BODY, TextSize = 14, TextColor3 = Ui.MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(22, 36), Size = UDim2.new(1, -240, 0, 36), ZIndex = 13 })
		local _, setLv = Ui.meter(row, pk.max, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 14), Size = UDim2.fromOffset(170, 8), ZIndex = 13 }, Ui.GOLD)
		setLv(lv / pk.max)
		local maxed = lv >= pk.max
		local canBuy = not maxed and (profile.tokens or 0) >= 1
		local pb = Ui.button(row, if maxed then "MAXED" else ("LV %d  ·  +1 TOKEN"):format(lv), { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -12), Size = UDim2.fromOffset(190, 42), ZIndex = 13 }, canBuy)
		local t = pb:FindFirstChild("Text") :: TextLabel
		t.TextSize = 15
		pb.Activated:Connect(function()
			if maxed then
				return
			end
			local res = request(Remotes.Shop, { action = "perk", key = pk.key })
			if res then
				rebirthStatus.Text = string.upper(res.message or "")
				rebirthStatus.TextColor3 = if res.ok then Ui.GREEN else Ui.RED
			end
		end)
	end
end

-- CARGO ----------------------------------------------------------------------------------

local cargoBody: Frame
local cargoInfo: TextLabel
local sellButton: ImageButton

render.cargo = function()
	if not profile then
		return
	end
	clear(cargoBody)
	cargoInfo.Text = ("%d / %d FISH   ·   WORTH %s"):format(#profile.cargo, profile.cargoCap, Ui.coinText(profile.cargoValue))
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(150, 120)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = cargoBody
	if #profile.cargo == 0 then
		Ui.label(cargoBody, { Text = "YOUR BUCKET IS EMPTY\nCAST FROM THE END OF A DOCK TO CATCH FISH", Font = Ui.TECH, TextSize = 17, TextColor3 = Ui.MUTED, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 60), ZIndex = 13 })
		grid.CellSize = UDim2.new(1, 0, 0, 260)
	end
	for i, c in profile.cargo do
		local f = Config.BY_ID[c.id]
		local card = Ui.panel(cargoBody, { Size = UDim2.fromOffset(150, 120), LayoutOrder = i, ZIndex = 12 })
		Ui.fish(card, c.id, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(130, 62), ZIndex = 13 })
		Ui.label(card, { Text = string.upper(Config.SIZES[c.size].name .. " " .. f.name), Font = Ui.TECH, TextSize = 13, TextWrapped = true, TextColor3 = rarityColor(f.rarity), TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(8, 66), Size = UDim2.new(1, -16, 0, 30), ZIndex = 13 })
		if (c.bonus or 0) > 0 then
			Ui.label(card, { Text = ("+%d%%"):format(c.bonus), Font = Ui.TECH, TextSize = 12, TextColor3 = Ui.CYAN, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 6), Size = UDim2.fromOffset(50, 14), ZIndex = 14 })
		end
		local rel = Ui.label(card, { Text = "RELEASE", Font = Ui.TECH, TextSize = 12, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 0, 16), ZIndex = 13 })
		local btn = Instance.new("TextButton")
		btn.BackgroundTransparency = 1
		btn.Text = ""
		btn.Size = UDim2.fromScale(1, 1)
		btn.ZIndex = 14
		btn.Parent = rel
		btn.Activated:Connect(function()
			request(Remotes.Fish, { action = "release", index = i })
		end)
	end
	local canSell = profile.passes.AUTO_SELL
	Ui.setText(sellButton, if canSell then "SELL ALL" else "SELL TO ZORP")
	Ui.setActive(sellButton, canSell and #profile.cargo > 0)
end

-- WORLD 2 ---------------------------------------------------------------------------------

local w2Text: TextLabel
local w2Button: ImageButton
render.world2 = function()
	if not profile then
		return
	end
	if not Config.WORLD2_OPEN then
		w2Text.Text = "World 2 is under construction! Something stirs beyond the black hole... check back in a future update."
		Ui.setText(w2Button, "UNDER CONSTRUCTION")
		Ui.setStyle(w2Button, "grey")
		;(w2Button:FindFirstChild("Text") :: TextLabel).TextSize = 19
	elseif profile.world2 then
		w2Text.Text = "You've unlocked World 2! The gate opens in a future update."
		Ui.setText(w2Button, "UNLOCKED")
		Ui.setActive(w2Button, false)
	else
		w2Text.Text = "Something stirs beyond the black hole. Buy access to World 2 for " .. Ui.coinText(Config.WORLD2_COST) .. " coins."
		Ui.setText(w2Button, Ui.coinText(Config.WORLD2_COST))
		Ui.setActive(w2Button, profile.coins >= Config.WORLD2_COST)
	end
end

---------------------------------------------------------------- daily streak

function Menus.showStreak(info)
	local w = windows.streak
	local body = w:FindFirstChild("Body") :: Frame
	clear(body)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 8)
	list.Parent = body
	for i, base in info.rewards do
		local on = i == info.slot
		local d = Ui.panel(body, { Size = UDim2.fromOffset(76, 110), LayoutOrder = i, ZIndex = 12 }, on)
		Ui.label(d, { Text = "DAY " .. i, Font = Ui.TECH, TextSize = 13, TextColor3 = if on then Ui.CYAN else Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 16), ZIndex = 13 })
		Ui.image(d, if i == #info.rewards then Art.icon.luck else Art.ui.coin, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.fromOffset(34, 34), ImageColor3 = if i == #info.rewards then Ui.GOLD else Color3.new(1, 1, 1), ZIndex = 13 })
		Ui.label(d, { Text = if i == #info.rewards then "BOOST" else Ui.coinText(base), Font = Ui.TECH, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 0, 18), ZIndex = 13 })
		if i < info.slot then
			d.ImageTransparency = 0.5
		end
	end
	local sub = w:FindFirstChild("Sub") :: TextLabel
	sub.Text = ("DAY %d STREAK   ·   +%s COINS%s"):format(info.count, Ui.coinText(info.coins), if info.luck then "  +  RARE BOOST" else "")
	Menus.close()
	w.Visible = true
	syncBackdrop()
	Ui.pop(w)
end

---------------------------------------------------------------- build

function Menus.init(onProfile)
	gui = Ui.gui("Menus", 10)
	popGui = Ui.gui("Popups", 30)
	backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BorderSizePixel = 0
	backdrop.BackgroundColor3 = Color3.fromRGB(4, 2, 12)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 1
	backdrop.Visible = false
	backdrop.Parent = gui
	backdrop.Activated:Connect(function()
		Menus.close()
	end)
	local tg = Ui.gui("Toasts", 40)
	toastList = Ui.frame(tg, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), Size = UDim2.fromOffset(420, 400) })
	local tl = Instance.new("UIListLayout")
	tl.Padding = UDim.new(0, 8)
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tl.Parent = toastList

	-- upgrades (coins): opened at Captain Whiskers and the upgrade terminal
	local shop = window("shop", "Upgrades", Vector2.new(720, 640))
	-- shop (Robux only): the side Shop button and the + on the coins
	local rshop = window("robux", "Shop", Vector2.new(720, 640))
	local rs = Instance.new("ScrollingFrame")
	rs.BackgroundTransparency = 1
	rs.BorderSizePixel = 0
	rs.Position = UDim2.fromOffset(28, 80)
	rs.Size = UDim2.new(1, -56, 1, -100)
	rs.ScrollBarThickness = 4
	rs.ScrollBarImageColor3 = Ui.PURPLE
	rs.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rs.CanvasSize = UDim2.new()
	rs.ZIndex = 12
	rs.Parent = rshop
	robuxBody = rs
	local sc = Instance.new("ScrollingFrame")
	sc.BackgroundTransparency = 1
	sc.BorderSizePixel = 0
	sc.Position = UDim2.fromOffset(28, 80)
	sc.Size = UDim2.new(1, -56, 1, -136)
	sc.ScrollBarThickness = 4
	sc.ScrollBarImageColor3 = Ui.PURPLE
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sc.CanvasSize = UDim2.new()
	sc.ZIndex = 12
	sc.Parent = shop
	shopBody = sc
	shopStatus = Ui.label(shop, { Text = "", Font = Ui.TECH, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 28, 1, -46), Size = UDim2.new(1, -56, 0, 24), ZIndex = 12 })

	-- catalog
	local cat = window("catalog", "Cosmic Catalog", Vector2.new(900, 640))
	catDone = Ui.label(cat, { Text = "", Font = Ui.TECH, TextSize = 15, TextColor3 = Ui.CYAN, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -80, 0, 28), Size = UDim2.fromOffset(260, 20), ZIndex = 12 })
	local _, setDone = Ui.meter(cat, 20, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -80, 0, 52), Size = UDim2.fromOffset(260, 8), ZIndex = 12 })
	setCatDone = setDone
	for i, l in Config.LAYERS do
		local b = Ui.button(cat, l.name, { Position = UDim2.fromOffset(30 + (i - 1) * 212, 78), Size = UDim2.fromOffset(204, 44), ZIndex = 12 })
		local t = b:FindFirstChild("Text") :: TextLabel
		t.TextSize = 15
		b.Activated:Connect(function()
			catalogLayer = i
			render.catalog()
		end)
		catTabs[i] = b
	end
	local cs = Instance.new("ScrollingFrame")
	cs.BackgroundTransparency = 1
	cs.BorderSizePixel = 0
	cs.Position = UDim2.fromOffset(30, 136)
	cs.Size = UDim2.new(1, -60, 1, -160)
	cs.ScrollBarThickness = 4
	cs.ScrollBarImageColor3 = Ui.PURPLE
	cs.AutomaticCanvasSize = Enum.AutomaticSize.Y
	cs.CanvasSize = UDim2.new()
	cs.ZIndex = 12
	cs.Parent = cat
	catBody = cs

	-- quests
	local q = window("quests", "Quests", Vector2.new(640, 600))
	local qs = Instance.new("ScrollingFrame")
	qs.BackgroundTransparency = 1
	qs.BorderSizePixel = 0
	qs.Position = UDim2.fromOffset(30, 80)
	qs.Size = UDim2.new(1, -60, 1, -130)
	qs.ScrollBarThickness = 4
	qs.ScrollBarImageColor3 = Ui.PURPLE
	qs.AutomaticCanvasSize = Enum.AutomaticSize.Y
	qs.CanvasSize = UDim2.new()
	qs.ZIndex = 12
	qs.Parent = q
	questBody = qs
	questFoot = Ui.label(q, { Text = "", Font = Ui.TECH, TextSize = 14, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 30, 1, -44), Size = UDim2.new(1, -60, 0, 20), ZIndex = 12 })

	-- cargo
	local cg = window("cargo", "Bucket", Vector2.new(720, 580))
	cargoInfo = Ui.label(cg, { Text = "", Font = Ui.TECH, TextSize = 16, TextColor3 = Ui.CYAN, Position = UDim2.fromOffset(34, 74), Size = UDim2.fromOffset(500, 20), ZIndex = 12 })
	local cgs = Instance.new("ScrollingFrame")
	cgs.BackgroundTransparency = 1
	cgs.BorderSizePixel = 0
	cgs.Position = UDim2.fromOffset(30, 104)
	cgs.Size = UDim2.new(1, -60, 1, -184)
	cgs.ScrollBarThickness = 4
	cgs.ScrollBarImageColor3 = Ui.PURPLE
	cgs.AutomaticCanvasSize = Enum.AutomaticSize.Y
	cgs.CanvasSize = UDim2.new()
	cgs.ZIndex = 12
	cgs.Parent = cg
	cargoBody = cgs
	sellButton = Ui.button(cg, "SELL ALL", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.fromOffset(320, 50), ZIndex = 12 })
	sellButton.Activated:Connect(function()
		local res = request(Remotes.Shop, { action = "sell" })
		if res then
			Menus.toast(res.message or "", if res.ok then Ui.GOLD else Ui.RED)
		end
	end)

	-- world 2
	local w2 = window("world2", "World 2 Gate", Vector2.new(520, 320))
	w2Text = Ui.label(w2, { Text = "", Font = Ui.BODY, TextSize = 18, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(40, 90), Size = UDim2.new(1, -80, 0, 90), ZIndex = 12 })
	w2Button = Ui.button(w2, "", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.fromOffset(260, 50), ZIndex = 12 })
	w2Button.Activated:Connect(function()
		local res = request(Remotes.Shop, { action = "world2" })
		if res then
			Menus.toast(res.message or "", if res.ok then Ui.GOLD else Ui.RED)
		end
	end)

	-- daily streak
	local st = window("streak", "Daily Reward", Vector2.new(660, 300))
	Ui.frame(st, { Name = "Body", Position = UDim2.fromOffset(20, 84), Size = UDim2.new(1, -40, 0, 112), ZIndex = 12 })
	Ui.label(st, { Name = "Sub", Text = "", Font = Ui.TECH, TextSize = 18, TextColor3 = Ui.GOLD, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 210), Size = UDim2.new(1, 0, 0, 24), ZIndex = 12 })
	local ok = Ui.button(st, "COLLECT", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(220, 46), ZIndex = 12 }, true)
	ok.Activated:Connect(function()
		Menus.close("streak")
	end)

	-- rebirth
	local rb = window("rebirth", "Rebirth", Vector2.new(720, 640))
	local rbs = Instance.new("ScrollingFrame")
	rbs.BackgroundTransparency = 1
	rbs.BorderSizePixel = 0
	rbs.Position = UDim2.fromOffset(30, 80)
	rbs.Size = UDim2.new(1, -60, 1, -130)
	rbs.ScrollBarThickness = 4
	rbs.ScrollBarImageColor3 = Ui.PURPLE
	rbs.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rbs.CanvasSize = UDim2.new()
	rbs.ZIndex = 12
	rbs.Parent = rb
	rebirthBody = rbs
	rebirthStatus = Ui.label(rb, { Text = "", Font = Ui.TECH, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 30, 1, -44), Size = UDim2.new(1, -60, 0, 22), ZIndex = 12 })

	-- settings
	local se = window("settings", "Settings", Vector2.new(660, 640))
	local ss = Instance.new("ScrollingFrame")
	ss.BackgroundTransparency = 1
	ss.BorderSizePixel = 0
	ss.Position = UDim2.fromOffset(30, 80)
	ss.Size = UDim2.new(1, -60, 1, -160)
	ss.ScrollBarThickness = 4
	ss.ScrollBarImageColor3 = Ui.PURPLE
	ss.AutomaticCanvasSize = Enum.AutomaticSize.Y
	ss.CanvasSize = UDim2.new()
	ss.ZIndex = 12
	ss.Parent = se
	local sl = Instance.new("UIListLayout")
	sl.Padding = UDim.new(0, 8)
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.Parent = ss
	local order = 0
	local function heading(text: string)
		order += 1
		Ui.label(ss, { Text = string.upper(text), Font = Ui.TITLE, TextSize = 15, TextColor3 = Ui.CYAN, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 30), TextYAlignment = Enum.TextYAlignment.Bottom })
	end
	local function row(title: string, sub: string): Frame
		order += 1
		local r = Ui.frame(ss, { LayoutOrder = order, BackgroundTransparency = 0.5, BackgroundColor3 = Color3.fromRGB(30, 22, 70), Size = UDim2.new(1, -8, 0, 64) })
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = r
		Ui.label(r, { Text = string.upper(title), Font = Ui.TECH, TextSize = 19, Position = UDim2.fromOffset(16, 9), Size = UDim2.new(1, -310, 0, 24) })
		Ui.label(r, { Text = sub, Font = Ui.BODY, TextSize = 14, TextColor3 = Ui.MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(16, 34), Size = UDim2.new(1, -310, 0, 28) })
		return Ui.frame(r, { Name = "Control", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(280, 42) })
	end
	local setters = {}
	local function slider(key, title, sub)
		local _, set = Ui.slider(row(title, sub), { Size = UDim2.fromScale(1, 1) }, Settings.get(key), function(v)
			Settings.set(key, v)
		end)
		setters[key] = set
	end
	local function toggle(key, title, sub)
		local _, set = Ui.toggle(row(title, sub), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(130, 42) }, function(v)
			Settings.set(key, v)
		end)
		setters[key] = set
	end
	local function choice(key, title, sub, options)
		local _, set = Ui.choice(row(title, sub), { Size = UDim2.fromScale(1, 1) }, options, function(v)
			Settings.set(key, v)
		end)
		setters[key] = set
	end

	heading("Audio")
	slider("music", "Music", "Background music volume (M turns it on and off)")
	slider("sfx", "Sound Effects", "Casting, splashes and catch sounds")
	heading("Visuals")
	choice("auras", "Fish Auras", "Glow around rare fish and the God Rod", { { "all", "ALL" }, { "mine", "MINE" }, { "off", "OFF" } })
	toggle("lowGfx", "Low Graphics", "Turns off shadows and lobby effects for smoother play")
	toggle("hidePlayers", "Hide Other Players", "Hides everyone else and the fish they hold")
	toggle("shake", "Screen Shake", "Camera shake and impact pauses when fish bite and land")
	heading("Interface")
	toggle("announce", "Catch Announcements", "Pop-ups when other players catch big fish")
	heading("Controls")
	for _, k in { { "F", "Start / stop fishing at a dock" }, { "HOLD CLICK / SPACE", "Charge your cast, let go to throw" }, { "CLICK / SPACE", "Reel in when a fish bites" }, { "SHIFT", "Hold to sprint" }, { "M", "Music on / off" } } do
		order += 1
		local r = Ui.frame(ss, { LayoutOrder = order, Size = UDim2.new(1, -8, 0, 26) })
		Ui.label(r, { Text = k[1], Font = Ui.TECH, TextSize = 16, TextColor3 = Ui.GOLD, Position = UDim2.fromOffset(16, 0), Size = UDim2.fromOffset(210, 26) })
		Ui.label(r, { Text = k[2], Font = Ui.BODY, TextSize = 16, Position = UDim2.fromOffset(230, 0), Size = UDim2.new(1, -240, 0, 26) })
	end

	local reset = Ui.button(se, "RESET TO DEFAULTS", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.fromOffset(300, 48), ZIndex = 12 })
	reset.Activated:Connect(function()
		Settings.reset()
		Menus.toast("Settings reset", Ui.CYAN)
	end)
	render.settings = function()
		for key, set in setters do
			set(Settings.get(key))
		end
	end
	Settings.onChanged(function(key, v)
		if setters[key] then
			setters[key](v)
		end
	end)
	render.settings()

	_ = onProfile
end

function Menus.setProfile(p)
	profile = p
	for name, w in windows do
		if w.Visible and render[name] and name ~= "quests" then
			render[name]()
		end
	end
	if windows.quests and windows.quests.Visible and lastQuestData then
		questRows(lastQuestData) -- Zorp's quest comes from the profile
	end
end

return Menus
