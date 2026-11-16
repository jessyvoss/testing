-- Fish in Space: first-time tutorial. Runs once, for players whose profile hasn't got tutorialDone. Zorp walks
-- you through the whole game in his talk box; a card at the top shows the current step (with a Skip button),
-- and a glowing marker points at where to go. Each step waits for you to actually do it. Finishing or skipping
-- saves tutorialDone on the server, so it never shows again.
-- The rest of the client reports what happens with Tutorial.signal(name):
--   fishStart, fishStop, state (flight/swim/aim), catch, zorp, open (menu name)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("FishInSpace")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = Shared:WaitForChild("Remotes")
local Ui = require(script.Parent:WaitForChild("Ui"))
local Dialog = require(script.Parent:WaitForChild("Dialog"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local player = Players.LocalPlayer
local Tutorial = {}
local running = false
local cancelled = false
local skipStep = false -- the SKIP STEP button: move on from the current step
local fired = {} -- [signal] = true since the step started

---------------------------------------------------------------- the card at the top
local gui = Ui.gui("Tutorial", 9) -- the step card: above the HUD, under open windows (the pointer stays on top)
local card = Ui.panel(gui, { Name = "Card", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90), Size = UDim2.fromOffset(410, 104), Visible = false })
local cardFit = Instance.new("UIScale")
cardFit.Name = "Fit" -- (its drop shadow follows a UIScale called Fit)
cardFit.Parent = card
local stepLabel = Ui.label(card, { Text = "", Font = Ui.TECH, TextSize = 14, TextColor3 = Ui.CYAN, Position = UDim2.fromOffset(26, 14), Size = UDim2.fromOffset(300, 18), ZIndex = 3 })
local doLabel = Ui.label(card, { Text = "", Font = Ui.TECH, TextSize = 17, TextColor3 = Ui.TEXT, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(24, 34), Size = UDim2.new(1, -124, 0, 44), ZIndex = 3 })
do
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(8, 4, 24)
	st.Thickness = 1.5
	st.Transparency = 0.4
	st.Parent = doLabel
end
local _, setProgress = Ui.meter(card, 11, { Position = UDim2.new(0, 24, 1, -20), Size = UDim2.new(1, -140, 0, 6), ZIndex = 3 })
local skipButton = Ui.button(card, "SKIP STEP", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(90, 40), ZIndex = 4 })
do
	local t = skipButton:FindFirstChild("Text") :: TextLabel
	t.TextSize = 14
end
-- the card sits centred just under the HUD's top row, at the HUD's scale (so it never covers the pills on a phone)
local function fitCard()
	local hudGui = Players.LocalPlayer.PlayerGui:FindFirstChild("Hud")
	local s = (hudGui and hudGui:GetAttribute("HudScale")) or 1
	local y = (hudGui and hudGui:GetAttribute("TopBottom")) or 76
	cardFit.Scale = s
	card.Position = UDim2.new(0.5, 0, 0, y + 12 * s)
end
fitCard()
task.spawn(function()
	local hudGui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Hud")
	hudGui:GetAttributeChangedSignal("TopBottom"):Connect(fitCard)
	hudGui:GetAttributeChangedSignal("HudScale"):Connect(fitCard)
	fitCard()
end)

local function showStep(i: number, total: number, text: string)
	if cancelled or not running then
		return
	end
	skipStep = false
	card.Visible = true
	stepLabel.Text = ("TUTORIAL  ·  STEP %d / %d"):format(i, total)
	doLabel.Text = string.upper(text)
	setProgress((i - 1) / total)
	doLabel.TextTransparency = 1
	TweenService:Create(doLabel, TweenInfo.new(0.35), { TextTransparency = 0 }):Play()
	Sounds.play("open", { pitch = 1.2 })
end

---------------------------------------------------------------- pointing at buttons
-- Spotlight: the rest of the screen dims, leaving a clear window around the button to press. Ripples pulse out of
-- the button and a bouncing arrow with "CLICK" points at it. It follows the button, and hides whenever the button
-- isn't on screen. Clicks still reach the button (the dim pieces don't take input).
local GuiService = game:GetService("GuiService")
local pointGui = Ui.gui("TutorialPointer", 32) -- above the HUD and menus, below the tutorial card and Zorp's talk box
pointGui.IgnoreGuiInset = false -- buttons report AbsolutePosition from below the top bar; match that
local DIM = 0.42
local dims = {}
for i = 1, 4 do
	dims[i] = Ui.frame(pointGui, { Name = "Dim", BackgroundTransparency = 1, BackgroundColor3 = Color3.fromRGB(4, 2, 14), Visible = false, Active = false })
end
local ripples = {}
for i = 1, 2 do
	local r = Ui.frame(pointGui, { Name = "Ripple", AnchorPoint = Vector2.new(0.5, 0.5), Visible = false })
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = r
	local st = Instance.new("UIStroke")
	st.Color = Ui.CYAN
	st.Thickness = 3
	st.Parent = r
	ripples[i] = { frame = r, stroke = st }
end
local pointer = Ui.label(pointGui, { Name = "Pointer", Text = "", Font = Ui.TITLE, TextSize = 46, TextColor3 = Ui.CYAN, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(60, 60), Visible = false })
local clickLabel = Ui.label(pointGui, { Name = "Click", Text = "CLICK", Font = Ui.TECH, TextSize = 17, TextColor3 = Color3.fromRGB(210, 252, 255), TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(70, 20), Visible = false })
for _, l in { pointer, clickLabel } do
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(8, 4, 24)
	st.Thickness = 3
	st.Parent = l
end
local pointTarget: GuiObject? = nil
local pointSince = 0

local function onScreen(g: GuiObject): boolean
	local x: Instance? = g
	while x do
		if x:IsA("GuiObject") and not x.Visible then
			return false
		end
		if x:IsA("LayerCollector") then
			return (x :: any).Enabled ~= false
		end
		x = x.Parent
	end
	return false
end

local function hidePointer()
	for _, d in dims do
		d.Visible = false
	end
	for _, r in ripples do
		r.frame.Visible = false
	end
	pointer.Visible = false
	clickLabel.Visible = false
end

local function pointAt(g: GuiObject?)
	if g ~= pointTarget then
		pointSince = os.clock()
	end
	pointTarget = g
	if not g then
		hidePointer()
	end
end

RunService.RenderStepped:Connect(function()
	local g = pointTarget
	if not g or not g.Parent or not onScreen(g) then
		hidePointer()
		return
	end
	local t = os.clock()
	local fade = math.clamp((t - pointSince) / 0.35, 0, 1)
	local pos, size = g.AbsolutePosition, g.AbsoluteSize
	local pad = 10
	local x0, y0 = pos.X - pad, pos.Y - pad
	local x1, y1 = pos.X + size.X + pad, pos.Y + size.Y + pad
	local inset = GuiService:GetGuiInset().Y
	-- four dark pieces around the clear window (the top one also covers the bar above the screen area)
	local rects = {
		{ UDim2.new(0, 0, 0, -inset - 4), UDim2.new(1, 0, 0, y0 + inset + 4) },
		{ UDim2.new(0, 0, 0, y1), UDim2.new(1, 0, 1, -y1 + 4) },
		{ UDim2.new(0, 0, 0, y0), UDim2.new(0, x0, 0, y1 - y0) },
		{ UDim2.new(0, x1, 0, y0), UDim2.new(1, -x1, 0, y1 - y0) },
	}
	for i, d in dims do
		d.Visible = true
		d.Position, d.Size = rects[i][1], rects[i][2]
		d.BackgroundTransparency = 1 - (1 - DIM) * fade
	end
	-- ripples pulsing out of the button
	local centre = pos + size / 2
	local base = math.max(size.X, size.Y)
	for i, r in ripples do
		local p = ((t * 0.8) + (i - 1) * 0.5) % 1
		r.frame.Visible = true
		r.frame.Position = UDim2.fromOffset(centre.X, centre.Y)
		local d = base * (0.75 + p * 0.9)
		r.frame.Size = UDim2.fromOffset(d, d * math.clamp(size.Y / size.X, 0.45, 1))
		r.stroke.Transparency = 1 - (1 - p) * 0.85 * fade
	end
	-- the arrow sits on the side with the most room and bobs toward the button, "CLICK" just beyond it
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 800)
	local bob = math.sin(t * 7) * 8
	pointer.Visible = true
	clickLabel.Visible = true
	pointer.TextTransparency = 1 - fade
	clickLabel.TextTransparency = 1 - fade
	if centre.X < vp.X * 0.3 then
		pointer.Text = "◀"
		pointer.Position = UDim2.fromOffset(x1 + 34 + bob, centre.Y)
		clickLabel.Position = UDim2.fromOffset(x1 + 96 + bob, centre.Y)
	elseif centre.X > vp.X * 0.7 then
		pointer.Text = "▶"
		pointer.Position = UDim2.fromOffset(x0 - 34 - bob, centre.Y)
		clickLabel.Position = UDim2.fromOffset(x0 - 96 - bob, centre.Y)
	else
		pointer.Text = "▼"
		pointer.Position = UDim2.fromOffset(centre.X, y0 - 30 - bob)
		clickLabel.Position = UDim2.fromOffset(centre.X, y0 - 66 - bob)
	end
end)

local updateTrail, hideTrail -- (the ground arrows, defined below)

---------------------------------------------------------------- the marker in the world
local marker = Instance.new("Part")
marker.Name = "TutorialMarker"
marker.Anchored = true
marker.CanCollide = false
marker.CanQuery = false
marker.CanTouch = false
marker.Transparency = 1
marker.Size = Vector3.new(1, 1, 1)
local beam = Instance.new("Part")
beam.Name = "Beam"
beam.Anchored = true
beam.CanCollide = false
beam.CanQuery = false
beam.CanTouch = false
beam.Material = Enum.Material.Neon
beam.Color = Ui.CYAN
beam.Transparency = 0.65
beam.Shape = Enum.PartType.Cylinder
beam.Size = Vector3.new(40, 1.2, 1.2)
beam.CastShadow = false
local ring = Instance.new("Part")
ring.Name = "Ring"
ring.Anchored = true
ring.CanCollide = false
ring.CanQuery = false
ring.CanTouch = false
ring.Material = Enum.Material.Neon
ring.Color = Ui.CYAN
ring.Transparency = 0.35
ring.Shape = Enum.PartType.Cylinder
ring.Size = Vector3.new(0.2, 9, 9)
ring.CastShadow = false
local bb = Instance.new("BillboardGui")
bb.Size = UDim2.fromOffset(120, 80)
bb.AlwaysOnTop = true
bb.LightInfluence = 0
bb.MaxDistance = 2000
bb.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
bb.Parent = marker
local arrowLabel = Ui.label(bb, { Text = "▼", Font = Ui.TITLE, TextSize = 34, TextColor3 = Ui.CYAN, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 40) })
local distLabel = Ui.label(bb, { Text = "", Font = Ui.TECH, TextSize = 16, TextColor3 = Ui.TEXT, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 20) })
for _, l in { arrowLabel, distLabel } do
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(8, 4, 24)
	st.Thickness = 2
	st.Parent = l
end
local target: Vector3? = nil
local function setTarget(pos: Vector3?)
	if pos and (cancelled or not running) then
		pos = nil
	end
	target = pos
	local on = pos ~= nil
	marker.Parent = if on then workspace else nil
	beam.Parent = if on then workspace else nil
	ring.Parent = if on then workspace else nil
	if not on then
		hideTrail()
	end
end
RunService.RenderStepped:Connect(function()
	if not target then
		return
	end
	local t = os.clock()
	marker.CFrame = CFrame.new(target)
	beam.CFrame = CFrame.new(target + Vector3.new(0, 20, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.CFrame = CFrame.new(target + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	local pulse = 1 + math.sin(t * 4) * 0.12
	ring.Size = Vector3.new(0.2, 9 * pulse, 9 * pulse)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 9 + math.sin(t * 5) * 0.8, 0)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		distLabel.Text = ("%dm"):format(math.floor((root.Position - target).Magnitude / 3.57 + 0.5))
		local feet = root.Position - Vector3.new(0, 2.5, 0)
		updateTrail(feet, target, char)
	end
end)

---------------------------------------------------------------- arrows on the ground
-- A trail of glowing chevrons from you toward the marker, following the ground and rippling toward it.
local TRAIL_N, TRAIL_GAP = 10, 5.5
local trailFolder = Instance.new("Folder")
trailFolder.Name = "TutorialTrail"
local chevrons = {}
local function arm()
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Ui.CYAN
	p.Size = Vector3.new(0.55, 0.12, 2.6)
	p.Parent = trailFolder
	return p
end
for i = 1, TRAIL_N do
	chevrons[i] = { arm(), arm() }
end
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
function hideTrail()
	trailFolder.Parent = nil
end
function updateTrail(from: Vector3, to: Vector3, char: Model?)
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local dist = flat.Magnitude
	if dist < 8 then
		hideTrail()
		return
	end
	trailFolder.Parent = workspace
	rayParams.FilterDescendantsInstances = { trailFolder, char, marker, beam, ring }
	local dir = flat.Unit
	local now = os.clock()
	for i, c in chevrons do
		local along = 4 + (i - 1) * TRAIL_GAP
		local show = along < dist - 5
		local p = from + dir * along
		local hit = show and workspace:Raycast(p + Vector3.new(0, 8, 0), Vector3.new(0, -30, 0), rayParams)
		if not hit then
			c[1].Transparency, c[2].Transparency = 1, 1
		else
			local y = hit.Position.Y + 0.12
			local tip = Vector3.new(p.X, y, p.Z) + dir * 1.1
			-- a ripple running toward the target, fading out toward the far end
			local wave = (math.sin(now * 6 - i * 0.9) + 1) / 2
			local tr = 0.15 + (1 - wave) * 0.5 + (i / TRAIL_N) * 0.2
			for k, side in { 1, -1 } do
				local back = (CFrame.fromAxisAngle(Vector3.yAxis, math.rad(38 * side)) * CFrame.new(dir)).Position
				local centre = tip - back * 1.3
				c[k].CFrame = CFrame.lookAt(centre, tip)
				c[k].Transparency = tr
			end
		end
	end
end

---------------------------------------------------------------- where things are
local function rootPos(): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

local function nearestPier()
	local pos = rootPos() or Vector3.zero
	local best, bestD
	for _, p in Config.PIERS do
		local d = (p.cframe.Position - pos).Magnitude
		if not bestD or d < bestD then
			best, bestD = p, d
		end
	end
	return best
end

local function nearestZorp(): Vector3?
	local pos = rootPos() or Vector3.zero
	local best, bestD
	for _, z in workspace:GetDescendants() do
		if z.Name == "QuestAlien" and z:IsA("Model") then
			local d = (z:GetPivot().Position - pos).Magnitude
			if not bestD or d < bestD then
				best, bestD = z:GetPivot().Position, d
			end
		end
	end
	return best
end

local function catPos(): Vector3?
	local m = workspace:FindFirstChild("Merchant", true)
	return m and m:GetPivot().Position + Vector3.new(0, 0, 0)
end

---------------------------------------------------------------- waiting
local function waitFor(check: () -> boolean)
	while not cancelled and not skipStep and not check() do
		task.wait(0.15)
	end
	return not cancelled
end

local function waitSignal(name: string)
	fired[name] = nil
	return waitFor(function()
		return fired[name] == true
	end)
end

-- point at a button and wait for `signal`; while a menu is open in front of it, ask them to close it first
local currentCtx = nil
local function guide(btn: GuiObject?, text: string, signal: string, window: string?)
	fired[signal] = nil
	local lastClosing = nil
	while not cancelled and not skipStep and not fired[signal] do
		local w = currentCtx and currentCtx.openWindow and currentCtx.openWindow()
		if window and w and w.Name == window then
			break -- already there
		end
		local closing = w ~= nil and btn ~= nil and not btn:IsDescendantOf(w)
		if closing ~= lastClosing then
			lastClosing = closing
			if closing then
				doLabel.Text = "CLOSE THIS MENU FIRST (THE X AT ITS TOP RIGHT)"
				pointAt(w:FindFirstChild("Close"))
			else
				doLabel.Text = string.upper(text)
				pointAt(btn)
			end
		end
		task.wait(0.15)
	end
	pointAt(nil)
	return not cancelled
end

local function talk(lines: { string })
	if cancelled or skipStep then
		return
	end
	Dialog.say("Zorp", lines)
	task.wait(0.2)
	waitFor(function()
		return not Dialog.isOpen()
	end)
end

function Tutorial.signal(name: string, arg: any?)
	if not running then
		return
	end
	fired[name] = true
	if arg ~= nil then
		fired[name .. ":" .. tostring(arg)] = true
	end
end

-- Studio only: test the steps without playing them (ReplicatedStorage.DevTutorialSignal:Fire("catch"))
if RunService:IsStudio() then
	local dev = Instance.new("BindableEvent")
	dev.Name = "DevTutorialSignal"
	dev.Event:Connect(function(name, arg)
		if name == "skipAll" then
			Tutorial.skipAll() -- (e.g. before recording the trailer)
			return
		end
		Tutorial.signal(name, arg)
	end)
	dev.Parent = ReplicatedStorage
end

function Tutorial.active(): boolean
	return running
end

---------------------------------------------------------------- the steps
local STEPS = 11

local function finish(skipped: boolean)
	running = false
	setTarget(nil)
	pointAt(nil)
	card.Visible = false
	pcall(Remotes.Shop.InvokeServer, Remotes.Shop, { action = "tutorialDone" })
	if not skipped then
		Sounds.play("sparkle")
	end
end

-- stop the whole tutorial at once (Studio's DevTutorialSignal "skipAll")
function Tutorial.skipAll()
	if running then
		finish(true)
		Dialog.stop()
	end
end

skipButton.Activated:Connect(function()
	if running then
		skipStep = true
		Dialog.stop()
	end
end)

local function run(ctx)
	currentCtx = ctx
	-- let the welcome pop-ups (daily reward) open and close first
	task.wait(3)
	waitFor(function()
		return not ctx.menusOpen()
	end)
	task.wait(0.6)

	-- 1. welcome
	showStep(1, STEPS, "Meet Zorp")
	talk({ ("Hey there, %s! I'm Zorp."):format(Players.LocalPlayer.DisplayName), "Welcome to Fish in Space. The sea out here is full of strange fish...", "Let me show you how it all works!" })

	-- 2. walk out onto a dock
	showStep(2, STEPS, "Walk out onto a dock (follow the marker)")
	local pier = nearestPier()
	setTarget((pier.cframe * CFrame.new(pier.size.X * 0.15, 0.5, 0)).Position)
	if not waitFor(function()
		local p = rootPos()
		return p ~= nil and Config.fishPier(p) ~= nil
	end) then
		return
	end
	setTarget(nil)

	-- 3. start fishing
	showStep(3, STEPS, "Press START FISHING (or F)")
	if not guide(ctx.ui and ctx.ui.fish, "Press START FISHING (or F)", "fishStart") then
		return
	end

	-- 4. cast
	showStep(4, STEPS, "Hold click or SPACE to charge, then let go to cast")
	if not waitSignal("state:flight") then
		return
	end

	-- 5. catch a fish
	showStep(5, STEPS, "Hold to reel in, tap to nudge the hook. Touch a fish to hook it!")
	if not waitSignal("catch") then
		return
	end

	-- 6. leave
	showStep(6, STEPS, "Nice catch! Press LEAVE (or F) to head back")
	if not guide(ctx.ui and ctx.ui.leave, "Nice catch! Press LEAVE (or F) to head back", "fishStop") then
		return
	end

	-- 7. sell to Zorp
	showStep(7, STEPS, "Sell your fish to Zorp: walk up and press E")
	setTarget(nearestZorp())
	if not waitSignal("zorp") then
		return
	end
	setTarget(nil)
	task.wait(0.3)
	waitFor(function()
		return not Dialog.isOpen()
	end)

	-- 8. upgrades at the shop
	showStep(8, STEPS, "Spend your coins: visit Captain Whiskers at the shop")
	fired["open:shop"] = nil
	talk({ "Coins buy upgrades from Captain Whiskers at the shop.", "Follow the marker and say hi!" })
	setTarget(catPos())
	if not waitFor(function()
		local w = ctx.openWindow and ctx.openWindow()
		return fired["open:shop"] == true or (w ~= nil and w.Name == "Upgrades")
	end) then
		return
	end
	setTarget(nil)
	talk({
		"Here's the Upgrades shop!",
		"Line Length lets your hook sink deeper.",
		"Distance Throw casts farther out, and rarer fish live farther out.",
		"Better Bait lets rarer fish bite, and a bigger Bucket carries more fish.",
		"Hook Modification reels faster. Close it when you're ready.",
	})

	-- 9. catalog
	showStep(9, STEPS, "Open your CATALOG (left side)")
	if not guide(ctx.ui and ctx.ui.catalog, "Open your CATALOG (left side)", "open:catalog", "Cosmic Catalog") then
		return
	end
	talk({ "Every kind of fish you catch goes in your Catalog.", "Catch them all and you unlock the golden line!" })

	-- 10. quests
	showStep(10, STEPS, "Open QUESTS (left side)")
	if not guide(ctx.ui and ctx.ui.quests, "Open QUESTS (left side)", "open:quests", "Quests") then
		return
	end
	talk({ "Daily quests pay out coins. Check back every day!", "And once you've caught 4 kinds of fish, come find me. I'll have quests for you too." })

	-- 11. done
	showStep(11, STEPS, "You're ready to fish!")
	setProgress(1)
	talk({
		"That's everything!",
		"Deeper and farther out means rarer fish, so keep upgrading.",
		"Caught something amazing? Open your Catalog and press HOLD to carry your best fish around and show it off!",
		"The cog at the top right has your settings. Good luck out there!",
	})
	finish(false)
end

-- ctx = { menusOpen = () -> boolean }
function Tutorial.start(ctx)
	if running then
		return
	end
	running = true
	cancelled = false
	task.spawn(function()
		local ok, err = pcall(run, ctx)
		if not ok then
			warn("[FishInSpace] tutorial stopped:", err)
		end
		if running and not cancelled then
			finish(true)
		end
	end)
end

return Tutorial
