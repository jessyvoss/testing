-- Fish in Space: the fishing view (3D).
-- Cast from the dock: the camera follows the hook along a long arc out over the nebula sea, then
-- dives with it. Fish (pictures with name tags) swim around in 3D; the hook sinks on its own,
-- WASD / the thumbstick steers it, the mouse looks around, and holding the button reels it in.
-- Anything that touches the hook latches on. Reeling to the surface flies the hook back to you.
-- Server depths are in "sea units"; here 1 unit = DS studs below the nebula surface.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("FishInSpace")
local Config = require(Shared:WaitForChild("Config"))
local Art = require(Shared:WaitForChild("Art"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local View = {}

---------------------------------------------------------------- tuning
local WATER_Y = -12 -- the nebula surface
local DS = 0.55 -- studs per sea unit of depth (deeper dives than the old side view)
local REACH_SCALE = 0.45 -- studs per sea unit of cast reach (the first cast lands ~117 studs out)
local SINK_SPEED = 7 -- studs per second (x Hook Modification)
local STEER_SPEED = 9 -- studs per second sideways while underwater
local REEL_SCALE = 0.32 -- studs per second per reel point
local CATCH_RADIUS = 2.4
local FISH_SCALE = 0.17 -- studs per old size unit
local CAM_DIST = 13
local C = Config.CAST
local PIVOT = C.rodTip

local WATER_TINT = { -- violet glow -> indigo -> magenta haze -> the void
	Color3.fromRGB(128, 84, 230),
	Color3.fromRGB(80, 56, 200),
	Color3.fromRGB(120, 40, 150),
	Color3.fromRGB(30, 12, 66),
}
local function tintAt(depthUnits: number): Color3
	local L = Config.LAYERS
	local prevMid, prevCol = 0, WATER_TINT[1]
	for i, l in L do
		local mid = (l.from + l.to) / 2
		if depthUnits <= mid then
			return prevCol:Lerp(WATER_TINT[i], if mid > prevMid then (depthUnits - prevMid) / (mid - prevMid) else 1)
		end
		prevMid, prevCol = mid, WATER_TINT[i]
	end
	return WATER_TINT[#WATER_TINT]
end
local SIZE_BY_RARITY = { Junk = 16, Common = 18, Uncommon = 23, Rare = 28, Epic = 36 }

---------------------------------------------------------------- state
local gui: ScreenGui
local hud: Frame
local depthPanel: Frame
local depthLabel: TextLabel
local layerLabel: TextLabel
local hookIcons: Frame
local hintLabel: TextLabel
local bannerLabel: TextLabel
local autoBadge: TextLabel
local powerBar: Frame

local folder: Folder
local hookPart: BasePart
local lineParts = {}
local surfacePart: BasePart?
local dustPart: BasePart
local dustFx: ParticleEmitter
local gasFx: ParticleEmitter
local seaFog: ColorCorrectionEffect?
local savedAtmo
local savedExposure
local blackHolePart: BasePart?
local blackHoleSaved

local character: Model?
local root: BasePart?
local rod: BasePart?
local F = Vector3.new(0, 0, -1) -- out to sea
local R = Vector3.new(1, 0, 0) -- to the right
local base = Vector3.zero -- on the surface, straight out in front of the dock

local state = "off" -- off | aim | charge | waiting | flight | swim | land
local cast -- the server's cast data
local hook = Vector3.zero
local flightFrom, flightTo, flightPeak, flightTime = Vector3.zero, Vector3.zero, 0, 1
local landFrom = Vector3.zero
local t = 0
local holding = false
local fishes = {}
local hooked = {}
local maxDepthSeen = 0
local lastLayer = 0
local onFinish: (({ number }) -> ())?
local onState: ((string) -> ())?
local autoMode = false
local autoTarget
local autoNextThink = 0
local camCF = CFrame.new()
local camYaw = 0
local sounds = {}

local function depthUnitsOf(p: Vector3): number
	return math.max(0, (WATER_Y - p.Y) / DS)
end
local function maxDepthStuds(): number
	local units = if cast then (cast.maxLen + PIVOT.Y) else 40
	return math.max(6, units * DS)
end
local function castDistance(): number
	local reach = (cast and cast.reach) or C.minReach or 260
	return reach * REACH_SCALE
end

---------------------------------------------------------------- helpers
local function newPart(name: string, props): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props or {} do
		(p :: any)[k] = v
	end
	p.Parent = folder
	return p
end

local function sound(id: string, vol: number, speed: number?)
	local s = sounds[id]
	if not s then
		s = Instance.new("Sound")
		s.SoundId = id
		s.Parent = gui
		sounds[id] = s
	end
	s.Volume = vol
	s.PlaybackSpeed = speed or 1
	s:Play()
end
local SFX = {
	cast = "rbxasset://sounds/action_swim.mp3",
	splash = "rbxasset://sounds/impact_water.mp3",
	catch = "rbxasset://sounds/electronicpingshort.wav",
}

local function banner(text: string, color: Color3?)
	bannerLabel.Text = string.upper(text)
	bannerLabel.TextColor3 = color or Ui.CYAN
	bannerLabel.TextTransparency = 0
	local fade = TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(bannerLabel, fade, { TextTransparency = 1 }):Play()
	local st = bannerLabel:FindFirstChildOfClass("UIStroke")
	if st then
		st.Transparency = 0.35
		TweenService:Create(st, fade, { Transparency = 1 }):Play()
	end
end
View.banner = banner

local function refreshHookIcons()
	for _, c in hookIcons:GetChildren() do
		if c:IsA("ImageLabel") then
			c:Destroy()
		end
	end
	local cap = if cast then cast.hookCap else 1
	for i = 1, cap do
		Ui.image(hookIcons, Art.icon.hook, { Size = UDim2.fromOffset(20, 20), ImageColor3 = if i <= #hooked then Ui.GOLD else Ui.MUTED, ImageTransparency = if i <= #hooked then 0 else 0.4, ZIndex = 21, LayoutOrder = i })
	end
end

local function rodTip(): Vector3
	local tip = rod and rod:FindFirstChild("Tip")
	if tip then
		return (tip :: BasePart).Position
	end
	return if root then root.Position + F * 3 + Vector3.yAxis * 3 else Vector3.zero
end

---------------------------------------------------------------- build once
local function build()
	gui = Ui.gui("FishingView", 5)
	gui.Enabled = false
	hud = Ui.frame(gui, { Name = "Hud", Size = UDim2.fromScale(1, 1), ZIndex = 20 })
	depthPanel = Ui.panel(hud, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 140), Size = UDim2.fromOffset(190, 96), ZIndex = 20 })
	Ui.label(depthPanel, { Text = "DEPTH", Font = Ui.TECH, TextSize = 14, TextColor3 = Ui.MUTED, Position = UDim2.fromOffset(22, 12), Size = UDim2.fromOffset(140, 16), ZIndex = 21 })
	depthLabel = Ui.label(depthPanel, { Text = "0 M", Font = Ui.TITLE, TextSize = 26, Position = UDim2.fromOffset(22, 30), Size = UDim2.fromOffset(150, 30), ZIndex = 21 })
	layerLabel = Ui.label(depthPanel, { Text = "", Font = Ui.TECH, TextSize = 14, TextColor3 = Ui.CYAN, Position = UDim2.fromOffset(22, 62), Size = UDim2.fromOffset(160, 18), ZIndex = 21 })
	hookIcons = Ui.frame(depthPanel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 10), Size = UDim2.fromOffset(110, 22), ZIndex = 22 })
	local hl = Instance.new("UIListLayout")
	hl.FillDirection = Enum.FillDirection.Horizontal
	hl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	hl.Padding = UDim.new(0, 6)
	hl.Parent = hookIcons
	powerBar = Ui.meter(hud, 14, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -70), Size = UDim2.fromOffset(420, 18), Visible = false, ZIndex = 21 })
	hintLabel = Ui.label(hud, { Text = "", Font = Ui.TECH, TextSize = 20, TextColor3 = Ui.TEXT, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -96), Size = UDim2.fromOffset(600, 26), ZIndex = 21 })
	bannerLabel = Ui.label(hud, { Text = "", Font = Ui.TITLE, TextSize = 20, TextColor3 = Ui.CYAN, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90), Size = UDim2.fromOffset(700, 40), TextTransparency = 1, ZIndex = 21 })
	autoBadge = Ui.label(hud, { Text = "AUTO FISHING", Font = Ui.TECH, TextSize = 16, TextColor3 = Ui.CYAN, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 140), Size = UDim2.fromOffset(240, 22), Visible = false, ZIndex = 21 })
	for _, l in { hintLabel, bannerLabel, autoBadge } do
		local st = Instance.new("UIStroke")
		st.Thickness = 1.5
		st.Transparency = if l == bannerLabel then 1 else 0.35
		st.Color = Color3.fromRGB(8, 4, 20)
		st.Parent = l
	end
end

local function buildWorld()
	folder = Instance.new("Folder")
	folder.Name = "MyFishing"
	folder.Parent = workspace
	hookPart = newPart("Hook", { Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 214, 110), Transparency = 1 })
	local hl = Instance.new("PointLight")
	hl.Color = Color3.fromRGB(255, 210, 120)
	hl.Range = 14
	hl.Brightness = 2
	hl.Parent = hookPart
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(2.6, 2.6)
	bb.LightInfluence = 0
	bb.AlwaysOnTop = true
	bb.Enabled = false
	bb.Parent = hookPart
	Ui.image(bb, Art.ui.hook, { Size = UDim2.fromScale(1, 1) })
	for i = 1, 24 do
		lineParts[i] = newPart("Line", { Size = Vector3.new(0.07, 0.07, 1), Material = Enum.Material.Neon, Color = Color3.fromRGB(225, 215, 255), Transparency = 1 })
	end
	-- nebula dust and gas clouds that travel with the camera underwater
	dustPart = newPart("Dust", { Transparency = 1, Size = Vector3.new(70, 40, 70) })
	dustFx = Instance.new("ParticleEmitter")
	dustFx.Texture = Art.ui.glowdot
	dustFx.Shape = Enum.ParticleEmitterShape.Box
	dustFx.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	dustFx.Rate = 60
	dustFx.Lifetime = NumberRange.new(4, 8)
	dustFx.Speed = NumberRange.new(0.1, 0.6)
	dustFx.LightEmission = 1
	dustFx.LightInfluence = 0
	dustFx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 0) })
	dustFx.Enabled = false
	dustFx.Parent = dustPart
	gasFx = Instance.new("ParticleEmitter")
	gasFx.Texture = "rbxasset://textures/particles/smoke_main.dds"
	gasFx.Shape = Enum.ParticleEmitterShape.Box
	gasFx.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	gasFx.Rate = 10
	gasFx.Lifetime = NumberRange.new(8, 12)
	gasFx.Speed = NumberRange.new(0.2, 0.7)
	gasFx.SpreadAngle = Vector2.new(180, 180)
	gasFx.Rotation = NumberRange.new(0, 360)
	gasFx.RotSpeed = NumberRange.new(-6, 6)
	gasFx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 10), NumberSequenceKeypoint.new(1, 24) })
	gasFx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.7), NumberSequenceKeypoint.new(1, 1) })
	gasFx.LightEmission = 1
	gasFx.LightInfluence = 0
	gasFx.Enabled = false
	gasFx.Parent = dustPart
end

-- A rod in the character's right hand, pointing forward and up.
local function attachRod(char: Model)
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local r = Instance.new("Part")
	r.Name = "FishingRod"
	r.Size = Vector3.new(0.14, 0.14, 5.2)
	r.Color = Color3.fromRGB(60, 44, 86)
	r.Material = Enum.Material.SmoothPlastic
	r.CanCollide = false
	r.CanQuery = false
	r.Massless = true
	r.CastShadow = false
	local tip = Instance.new("Part")
	tip.Name = "Tip"
	tip.Shape = Enum.PartType.Ball
	tip.Size = Vector3.new(0.22, 0.22, 0.22)
	tip.Material = Enum.Material.Neon
	tip.Color = Color3.fromRGB(120, 240, 255)
	tip.CanCollide = false
	tip.CanQuery = false
	tip.Massless = true
	tip.CFrame = r.CFrame * CFrame.new(0, 0, -2.6)
	tip.Parent = r
	local tw = Instance.new("WeldConstraint")
	tw.Part0, tw.Part1 = r, tip
	tw.Parent = tip
	local w = Instance.new("Weld")
	w.Part0 = hand
	w.Part1 = r
	w.C0 = CFrame.new(0, -hand.Size.Y * 0.4, 0) * CFrame.Angles(math.rad(32), 0, 0) * CFrame.new(0, 0, -2.3)
	w.Parent = r
	r.Parent = char
	rod = r
end

-- the glowing nebula surface (seen from above while the hook flies, and from below while diving)
local function makeSurface()
	if surfacePart then
		surfacePart:Destroy()
	end
	local center = base + F * 40
	surfacePart = newPart("NebulaSurface", {
		Size = Vector3.new(500, 0.2, 500),
		CFrame = CFrame.new(center.X, WATER_Y - 0.1, center.Z),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(70, 40, 150),
		Transparency = 0.8,
	})
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = Art.ui.glowdot
	sparkle.Shape = Enum.ParticleEmitterShape.Box
	sparkle.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	sparkle.Rate = 160
	sparkle.Lifetime = NumberRange.new(1.5, 3)
	sparkle.Speed = NumberRange.new(0.4, 1.4)
	sparkle.EmissionDirection = Enum.NormalId.Top
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparkle.LightEmission = 1
	sparkle.LightInfluence = 0
	sparkle.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150, 220, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 170, 240)) })
	sparkle.Parent = surfacePart
end

---------------------------------------------------------------- fish
local function clearFish(keepHooked: boolean)
	for i = #fishes, 1, -1 do
		local f = fishes[i]
		if not (keepHooked and f.isHooked) then
			f.part:Destroy()
			table.remove(fishes, i)
		end
	end
end

local function spawnFish(entry, center: Vector3)
	local def = Config.BY_ID[entry.id]
	local mv = Config.MOVE[def.rarity]
	local size = Config.SIZES[entry.size]
	local w = SIZE_BY_RARITY[def.rarity] * size.scale * FISH_SCALE
	local rng = Random.new(entry.seed)
	local a = rng:NextNumber(0, math.pi * 2)
	local r = rng:NextNumber(2, 20)
	local pos = Vector3.new(center.X + math.cos(a) * r, WATER_Y - math.max(1.5, entry.depth * DS), center.Z + math.sin(a) * r)
	local part = newPart("Fish", { Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(pos) })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(w, 0, w * 0.5 + 0.9, 0)
	bb.LightInfluence = 0
	bb.Brightness = 1.7
	bb.MaxDistance = 140
	bb.Parent = part
	local img = Ui.image(bb, Art.fish[def.id], { Position = UDim2.fromScale(0, 0.3), Size = UDim2.fromScale(1, 0.7) })
	local name = Ui.label(bb, { Text = string.upper(def.name), Font = Ui.TECH, TextScaled = true, TextColor3 = Config.RARITY[def.rarity].color, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 0.26) })
	local st = Instance.new("UIStroke")
	st.Thickness = 1
	st.Color = Color3.fromRGB(8, 4, 20)
	st.Parent = name
	local dirA = rng:NextNumber(0, math.pi * 2)
	table.insert(fishes, {
		entry = entry,
		def = def,
		part = part,
		bb = bb,
		img = img,
		w = w,
		pos = pos,
		baseY = pos.Y,
		center = center,
		dir = Vector3.new(math.cos(dirA), 0, math.sin(dirA)),
		speed = mv.speed * 0.13 * rng:NextNumber(0.8, 1.2),
		amp = mv.amp * 0.08,
		freq = mv.freq,
		dart = mv.dart,
		phase = rng:NextNumber(0, math.pi * 2),
		turnT = rng:NextNumber(1, 3),
		age = 0,
		rng = rng,
		flipped = false,
	})
end

local function updateFish(dt: number)
	local camRight = workspace.CurrentCamera.CFrame.RightVector
	for _, f in fishes do
		if f.isHooked then
			continue
		end
		f.age += dt
		f.turnT -= dt
		local sp = f.speed
		if f.turnT <= 0 then
			f.turnT = f.rng:NextNumber(1.2, 3.5)
			local a = math.atan2(f.dir.Z, f.dir.X) + f.rng:NextNumber(-1.2, 1.2)
			f.dir = Vector3.new(math.cos(a), 0, math.sin(a))
			if f.dart > 0 and f.rng:NextNumber() < f.dart then
				f.burst = 0.4
				f.baseY = math.clamp(f.baseY + f.rng:NextNumber(-3, 3), WATER_Y - 400, WATER_Y - 1.2)
			end
		end
		if f.burst and f.burst > 0 then
			f.burst -= dt
			sp *= 2.6
		end
		-- stay near the area the hook can reach
		local off = Vector3.new(f.pos.X - f.center.X, 0, f.pos.Z - f.center.Z)
		if off.Magnitude > 24 then
			f.dir = (-off).Unit
		end
		local np = f.pos + f.dir * sp * dt
		local y = f.baseY + math.sin(f.age * f.freq * math.pi + f.phase) * f.amp
		f.pos = Vector3.new(np.X, math.min(y, WATER_Y - 1), np.Z)
		f.part.CFrame = CFrame.new(f.pos)
		-- face the way it swims on screen
		local flip = f.dir:Dot(camRight) < 0
		if flip ~= f.flipped then
			f.flipped = flip
			f.img.ImageRectOffset = if flip then Vector2.new(512, 0) else Vector2.zero
			f.img.ImageRectSize = if flip then Vector2.new(-512, 256) else Vector2.zero
		end
	end
end

local function segDist(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then
		return (p - a).Magnitude
	end
	local tt = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	return (p - (a + ab * tt)).Magnitude
end

local function checkCatch(prevHook: Vector3)
	if not cast or #hooked >= cast.hookCap then
		return
	end
	for _, f in fishes do
		if #hooked >= cast.hookCap then
			break
		end
		if not f.isHooked and segDist(f.pos, prevHook, hook) < CATCH_RADIUS + f.w * 0.35 then
			f.isHooked = true
			f.entry.caught = true
			table.insert(hooked, f)
			sound(SFX.catch, 0.6, 0.9 + Config.RARITY[f.def.rarity].order * 0.12)
			local col = Config.RARITY[f.def.rarity].color
			banner((if f.entry.size >= 4 then Config.SIZES[f.entry.size].name .. " " else "") .. f.def.name .. " hooked!", col)
			refreshHookIcons()
			if #hooked >= cast.hookCap then
				hintLabel.Text = "HOOK FULL  ·  HOLD TO REEL IN"
			end
		end
	end
end

---------------------------------------------------------------- auto fish (a steady, average fisher)
local autoSteer = Vector3.zero
local function autoThink(now: number)
	if now < autoNextThink then
		return
	end
	autoNextThink = now + 0.2 + math.random() * 0.2
	if #hooked >= cast.hookCap then
		holding = true
		autoSteer = Vector3.zero
		return
	end
	holding = false
	if autoTarget and (autoTarget.isHooked or not table.find(fishes, autoTarget)) then
		autoTarget = nil
	end
	if not autoTarget then
		local best, bestD = nil, math.huge
		for _, f in fishes do
			if not f.isHooked then
				local order = Config.RARITY[f.def.rarity].order
				local skip = order >= 3 and math.random() > Config.AUTO_FISH_SKILL
				local d = (f.pos - hook).Magnitude
				if not skip and d < bestD then
					best, bestD = f, d
				end
			end
		end
		autoTarget = best
	end
	if autoTarget then
		local d = autoTarget.pos - hook
		autoSteer = Vector3.new(d.X, 0, d.Z)
		autoSteer = if autoSteer.Magnitude > 1 then autoSteer.Unit else Vector3.zero
		holding = autoTarget.pos.Y > hook.Y + 2
	end
end

---------------------------------------------------------------- per frame
local function drawLine()
	local out = state == "flight" or state == "swim" or state == "land"
	local a = rodTip()
	local b = hook
	local slack = if state == "flight" then 4 else 1.5
	local ctrl = (a + b) / 2 - Vector3.yAxis * slack
	local prev = a
	for i, seg in lineParts do
		local tt = i / #lineParts
		local p = a:Lerp(ctrl, tt):Lerp(ctrl:Lerp(b, tt), tt)
		local len = (p - prev).Magnitude
		seg.Size = Vector3.new(0.07, 0.07, math.max(0.01, len))
		if len > 0.001 then
			seg.CFrame = CFrame.lookAt((p + prev) / 2, p)
		end
		seg.Transparency = if out then 0.15 else 1
		prev = p
	end
	hookPart.CFrame = CFrame.new(hook)
	hookPart.Transparency = if out then 0 else 1
	local hb = hookPart:FindFirstChildOfClass("BillboardGui")
	if hb then
		hb.Enabled = out
	end
	for i, f in hooked do
		f.pos = hook - Vector3.yAxis * (0.8 + i * f.w * 0.3)
		f.part.CFrame = CFrame.new(f.pos)
	end
end

local function lookYaw(): number
	-- the mouse looks around while the hook is out (left/right of the screen turns the view)
	if UserInputService.MouseEnabled then
		local vp = workspace.CurrentCamera.ViewportSize
		local m = UserInputService:GetMouseLocation()
		local x = math.clamp((m.X / math.max(vp.X, 1) - 0.5) * 2, -1, 1)
		return x * math.rad(75)
	end
	return 0
end

local function underwaterLook(depthUnits: number)
	local under = workspace.CurrentCamera.CFrame.Position.Y < WATER_Y
	local tint = tintAt(depthUnits)
	if seaFog then
		seaFog.Enabled = under
		if under then
			seaFog.TintColor = Color3.new(0.55 + tint.R * 0.6, 0.55 + tint.G * 0.6, 0.6 + tint.B * 0.5)
			seaFog.Brightness = -math.clamp(depthUnits / 900, 0, 0.25)
		end
	end
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo and savedAtmo then
		if under then
			atmo.Density = math.clamp(0.42 + depthUnits / 900, 0, 0.75)
			atmo.Color = tint
			atmo.Decay = tint:Lerp(Color3.new(0, 0, 0), 0.5)
			atmo.Haze = 0.6
			atmo.Glare = 0
		else
			atmo.Density, atmo.Color, atmo.Decay, atmo.Haze, atmo.Glare = savedAtmo.Density, savedAtmo.Color, savedAtmo.Decay, savedAtmo.Haze, savedAtmo.Glare
		end
	end
	dustFx.Enabled = under
	gasFx.Enabled = under and depthUnits > 4
	local li = Config.layerAt(depthUnits)
	local dustCols = { Color3.fromRGB(120, 255, 230), Color3.fromRGB(170, 140, 255), Color3.fromRGB(255, 120, 210), Color3.fromRGB(255, 150, 90) }
	local gasCols = { Color3.fromRGB(170, 120, 255), Color3.fromRGB(110, 90, 255), Color3.fromRGB(220, 90, 220), Color3.fromRGB(120, 50, 160) }
	dustFx.Color = ColorSequence.new(dustCols[li])
	gasFx.Color = ColorSequence.new(gasCols[li], gasCols[math.min(li + 1, #gasCols)])
end

local function placeCamera(dt: number)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	local want
	if state == "aim" or state == "charge" or state == "waiting" or not cast then
		-- behind your shoulder, looking out over the sea
		local p = if root then root.Position else base
		want = CFrame.lookAt(p - F * 9 + Vector3.yAxis * 4.5 + R * 2.5, p + F * 40 - Vector3.yAxis * 8)
	elseif state == "flight" then
		-- chase the hook along its arc
		local travel = Vector3.new(flightTo.X - flightFrom.X, 0, flightTo.Z - flightFrom.Z).Unit
		local side = travel:Cross(Vector3.yAxis).Unit
		want = CFrame.lookAt(hook - travel * 18 + side * 5 + Vector3.yAxis * 5, hook + travel * 10)
	else
		-- orbit just behind the hook, looking where the mouse points
		camYaw += (lookYaw() - camYaw) * math.min(1, dt * 5)
		local d = (CFrame.fromAxisAngle(Vector3.yAxis, -camYaw) * CFrame.new(F)).Position
		local h = Vector3.new(d.X, 0, d.Z).Unit
		-- a little to the side so the line (which comes from the dock behind) isn't in your face
		local side = h:Cross(Vector3.yAxis).Unit
		local pos = hook - h * CAM_DIST + side * 6 + Vector3.yAxis * 2.5
		if state == "land" then
			pos = hook - h * CAM_DIST + side * 6 + Vector3.yAxis * 5
		end
		want = CFrame.lookAt(pos, hook + h * 8 - Vector3.yAxis * 1.5)
	end
	camCF = camCF:Lerp(want, 1 - math.exp(-dt * (if state == "flight" then 10 else 6)))
	camera.CFrame = camCF
	dustPart.CFrame = CFrame.new(camCF.Position + camCF.LookVector * 20)
end

local function finishCast()
	state = "land"
	landFrom = hook
	t = 0
	hintLabel.Text = ""
end

local function step(dt: number)
	local now = os.clock()
	if state == "flight" then
		t += dt / flightTime
		local tt = math.min(1, t)
		local p = flightFrom:Lerp(flightTo, tt)
		hook = p + Vector3.yAxis * (math.sin(tt * math.pi) * flightPeak)
		updateFish(dt)
		if tt >= 1 then
			state = "swim"
			sound(SFX.splash, 0.5)
			hintLabel.Text = if autoMode then "" else "WASD TO STEER  ·  HOLD TO REEL"
			if onState then
				onState("swim")
			end
		end
	elseif state == "swim" then
		if autoMode then
			autoThink(now)
		end
		local prevHook = hook
		local sinkMul = cast.sink or 1
		local v = Vector3.zero
		-- steer with WASD / thumbstick (the humanoid's move direction, relative to the camera)
		local steer = if autoMode then autoSteer else Vector3.zero
		if not autoMode then
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			if hum then
				local md = hum.MoveDirection
				steer = Vector3.new(md.X, 0, md.Z)
			end
		end
		v += steer * STEER_SPEED
		if holding then
			-- reel: up toward the surface and back toward the dock
			local toDock = Vector3.new(base.X - hook.X, 0, base.Z - hook.Z)
			local horiz = if toDock.Magnitude > 1 then toDock.Unit * 0.6 else Vector3.zero
			v += (Vector3.yAxis + horiz).Unit * (cast.reel or 45) * REEL_SCALE
		else
			v -= Vector3.yAxis * SINK_SPEED * sinkMul
		end
		hook += v * dt
		-- the line only reaches so deep, and only so far from where it landed
		local floorY = WATER_Y - maxDepthStuds()
		if hook.Y < floorY then
			hook = Vector3.new(hook.X, floorY, hook.Z)
			if not holding and not autoMode and #hooked < (cast.hookCap or 1) then
				hintLabel.Text = "LINE AT FULL LENGTH  ·  STEER OR REEL"
			end
		end
		local off = Vector3.new(hook.X - flightTo.X, 0, hook.Z - flightTo.Z)
		if off.Magnitude > 55 then
			local c = flightTo + off.Unit * 55
			hook = Vector3.new(c.X, hook.Y, c.Z)
		end
		local depth = depthUnitsOf(hook)
		maxDepthSeen = math.max(maxDepthSeen, depth)
		depthLabel.Text = ("%d M"):format(math.floor(depth))
		local li = Config.layerAt(depth)
		layerLabel.Text = string.upper(Config.LAYERS[li].name)
		if li > lastLayer then
			lastLayer = li
			if li > 1 then
				banner(Config.LAYERS[li].name, Config.RARITY[Config.TOP_RARITY[li]].color)
			end
		end
		updateFish(dt)
		checkCatch(prevHook)
		-- reeled back up to the surface: the hook flies home
		if (hook.Y >= WATER_Y - 0.2 and maxDepthSeen > 3) or now - (cast.t0 or now) > C.maxCastSeconds then
			finishCast()
		end
	elseif state == "land" then
		t += dt / 0.9
		local tt = math.min(1, t)
		local tip = rodTip()
		hook = landFrom:Lerp(tip, tt) + Vector3.yAxis * (math.sin(tt * math.pi) * 6)
		updateFish(dt)
		if tt >= 1 then
			local list = {}
			for _, f in hooked do
				table.insert(list, f.entry.i)
			end
			clearFish(false)
			table.clear(hooked)
			state = "aim"
			cast = nil
			hintLabel.Text = if autoMode then "" else "TAP TO CAST"
			if onState then
				onState("aim")
			end
			if onFinish then
				onFinish(list)
			end
		end
	else
		updateFish(dt)
	end
	depthPanel.Visible = state == "flight" or state == "swim" or state == "land"
	drawLine()
	placeCamera(dt)
	underwaterLook(depthUnitsOf(workspace.CurrentCamera.CFrame.Position))
end

---------------------------------------------------------------- public
function View.init(callbacks)
	build()
	onFinish = callbacks.onFinish
	onState = callbacks.onState
	RunService.RenderStepped:Connect(function(dt)
		if state ~= "off" then
			step(math.min(dt, 0.05))
		end
	end)
end

-- ctx = { character = Model, facing = degrees } for the dock you are standing on.
function View.open(ctx)
	ctx = ctx or {}
	character = ctx.character
	root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	F = (CFrame.Angles(0, math.rad(ctx.facing or 0), 0) * CFrame.new(0, 0, -1)).Position
	R = F:Cross(Vector3.yAxis).Unit
	if not folder or not folder.Parent then
		table.clear(lineParts)
		buildWorld()
	end
	if character and not character:FindFirstChild("FishingRod") then
		attachRod(character)
	end
	local p = if root then root.Position else Vector3.zero
	base = Vector3.new(p.X, WATER_Y, p.Z) + F * 4
	makeSurface()
	savedExposure = savedExposure or Lighting.ExposureCompensation
	Lighting.ExposureCompensation = savedExposure + 0.35
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo and not savedAtmo then
		savedAtmo = { Density = atmo.Density, Color = atmo.Color, Decay = atmo.Decay, Haze = atmo.Haze, Glare = atmo.Glare }
	end
	if not seaFog then
		seaFog = Instance.new("ColorCorrectionEffect")
		seaFog.Name = "FishingSeaTint"
		seaFog.Enabled = false
		seaFog.Parent = Lighting
	end
	-- the black hole hangs in the sky out in front of you while you fish
	local world = workspace:FindFirstChild("World")
	local sky = world and world:FindFirstChild("Sky")
	blackHolePart = sky and sky:FindFirstChild("BlackHole") :: BasePart?
	if blackHolePart then
		local bbg = blackHolePart:FindFirstChildOfClass("BillboardGui")
		blackHoleSaved = blackHoleSaved or { cf = blackHolePart.CFrame, size = bbg and bbg.Size }
		blackHolePart.CFrame = CFrame.new(p + F * 1600 + R * 500 + Vector3.yAxis * 420)
		if bbg then
			bbg.Size = UDim2.new(700, 0, 700, 0)
			bbg.Enabled = true
		end
	end
	gui.Enabled = true
	state = "aim"
	cast = nil
	hook = rodTip()
	camYaw = 0
	camCF = workspace.CurrentCamera.CFrame
	hintLabel.Text = if autoMode then "" else "TAP TO CAST"
	powerBar.Visible = false
	depthLabel.Text = "0 M"
	layerLabel.Text = string.upper(Config.LAYERS[1].name)
	refreshHookIcons()
end

function View.close()
	gui.Enabled = false
	state = "off"
	clearFish(false)
	table.clear(hooked)
	cast = nil
	for _, seg in lineParts do
		seg.Transparency = 1
	end
	if hookPart then
		hookPart.Transparency = 1
		local hb = hookPart:FindFirstChildOfClass("BillboardGui")
		if hb then
			hb.Enabled = false
		end
	end
	if surfacePart then
		surfacePart:Destroy()
		surfacePart = nil
	end
	if dustFx then
		dustFx.Enabled = false
		gasFx.Enabled = false
	end
	if seaFog then
		seaFog.Enabled = false
	end
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo and savedAtmo then
		atmo.Density, atmo.Color, atmo.Decay, atmo.Haze, atmo.Glare = savedAtmo.Density, savedAtmo.Color, savedAtmo.Decay, savedAtmo.Haze, savedAtmo.Glare
	end
	if savedExposure then
		Lighting.ExposureCompensation = savedExposure
	end
	if rod then
		rod:Destroy()
		rod = nil
	end
	if blackHolePart and blackHoleSaved then
		blackHolePart.CFrame = blackHoleSaved.cf
		local bbg = blackHolePart:FindFirstChildOfClass("BillboardGui")
		if bbg then
			if blackHoleSaved.size then
				bbg.Size = blackHoleSaved.size
			end
			bbg.Enabled = false
		end
	end
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if hum then
		camera.CameraSubject = hum
	end
end

function View.isOpen(): boolean
	return state ~= "off"
end

function View.state(): string
	return state
end

function View.setAuto(on: boolean)
	autoMode = on
	autoBadge.Visible = on
	if on then
		hintLabel.Text = ""
	end
end

-- Input: press/release from the main script (mouse, touch or key).
function View.press()
	if state == "aim" then
		state = "charge" -- a tap casts at full power
	elseif state == "swim" and not autoMode then
		holding = true
	end
end

function View.release(): number?
	if state == "charge" then
		state = "waiting"
		return 1
	elseif state == "swim" and not autoMode then
		holding = false
	end
	return nil
end

-- The server approved the cast: launch the hook along a long arc.
function View.launch(serverCast, p: number)
	if cast ~= serverCast then
		View.prepare(serverCast)
	end
	cast.t0 = os.clock()
	table.clear(hooked)
	lastLayer = 1
	maxDepthSeen = 0
	holding = false
	autoTarget = nil
	local dist = castDistance() * math.clamp(p or 1, 0.5, 1)
	flightFrom = rodTip()
	flightTo = base + F * dist
	flightPeak = 14 + dist * 0.22
	flightTime = 1.0 + dist / 140
	t = 0
	hook = flightFrom
	state = "flight"
	sound(SFX.cast, 0.6)
	hintLabel.Text = ""
	refreshHookIcons()
	if onState then
		onState("flight")
	end
end

-- The next cast is ready (fetched while you aim): its fish start swimming where the hook will land.
function View.prepare(serverCast)
	cast = serverCast
	clearFish(false)
	local center = base + F * castDistance()
	if cast.pool then
		for _, e in cast.pool do
			spawnFish(e, center)
		end
	end
	refreshHookIcons()
end

-- The server said no (cargo full etc.): go back to aiming.
function View.abort(message: string?)
	state = "aim"
	hintLabel.Text = string.upper(message or "TAP TO CAST")
end

-- For auto fish: start a full-power cast right away.
function View.autoCharge()
	if state == "aim" then
		state = "waiting"
		return 1
	end
	return nil
end

return View
