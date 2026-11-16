-- Fish in Space: the fishing view.
-- Fishing happens in the real world: the camera swings to a flat side view of your character on
-- the dock, and the hook, line and fish live on a vertical plane straight out from where you stand.
-- The hook swings on its line in an arc back toward the dock; holding reels in (up and toward the
-- dock), taps make small adjustments. Fish swim past by rarity; touching one hooks it.
-- Positions are worked out in "sea units" (x = out from the dock, y = depth below the water,
-- 4 units per stud) and then placed in the world.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("FishInSpace")
local Config = require(Shared:WaitForChild("Config"))
local Art = require(Shared:WaitForChild("Art"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local View = {}

local AIM_VIEW_H = 62 -- sea units visible top to bottom while aiming: a close shot of you and your rod
local SWIM_VIEW_H = 175 -- while the hook is out (middle distance: you see fish coming)
local viewH = AIM_VIEW_H
local AIM_CAM = Vector2.new(6, -166) -- centred on the character standing on the dock
local S = 0.25 -- studs per sea unit
local FOV = 40
local CAM_SIDE = 1 -- 1: camera on the player's right, so the sea runs to the right of the screen. -1 flips it.
local WATER_Y = -12 -- the cosmic sea sits well below the docks
-- underwater tint per layer: what the water itself looks like as you sink (lighter than black so
-- the glowing fish stand out against a coloured haze)
local WATER_TINT = { -- the nebula sea: violet glow -> indigo -> magenta haze -> the void
	Color3.fromRGB(128, 84, 230),
	Color3.fromRGB(80, 56, 200),
	Color3.fromRGB(120, 40, 150),
	Color3.fromRGB(30, 12, 66),
}
local function waterTint(depth: number): Color3
	-- blend between the middles of neighbouring layers
	local L = Config.LAYERS
	local prevMid, prevCol = 0, WATER_TINT[1]
	for i, l in L do
		local mid = (l.from + l.to) / 2
		if depth <= mid then
			return prevCol:Lerp(WATER_TINT[i], if mid > prevMid then (depth - prevMid) / (mid - prevMid) else 1)
		end
		prevMid, prevCol = mid, WATER_TINT[i]
	end
	return WATER_TINT[#WATER_TINT]
end
local fill: PointLight
local backdrop: BasePart
local savedExposure
local BACKDROP_GAP = 26 -- studs behind the fishing plane
local BACKDROP_DEPTH = 112 -- studs of sea it covers
local C = Config.CAST
local PIVOT = C.rodTip

local gui: ScreenGui
local root: Frame
local folder: Folder -- this player's local fishing parts (hook, line, fish, dust)
local origin = Vector3.zero -- the world point for sea (0, 0)
local F = Vector3.new(0, 0, -1) -- out to sea
local R = Vector3.new(1, 0, 0) -- toward the camera
local character: Model?
local rod: BasePart?
local hookPart: BasePart
local dust: BasePart
local dustFx: ParticleEmitter
local gasFx: ParticleEmitter? -- nebula gas clouds drifting around the view when deep
local blackHolePart: BasePart?
local blackHoleSaved
local savedWater
local newPart -- defined with the scene builders below
local seaFog: ColorCorrectionEffect? = nil
local holeRegion: Region3? = nil
local surfacePart: BasePart? = nil
-- The lobby hides the sea surface (the island floats in open space); the fishing view shows it.
local function setSea(mode: string)
	local T = workspace.Terrain
	local tr = T:GetAttribute(mode .. "WaterTransparency")
	if tr == nil then
		return
	end
	T.WaterTransparency = tr
	T.WaterReflectance = T:GetAttribute(mode .. "WaterReflectance") or T.WaterReflectance
	T.WaterWaveSize = T:GetAttribute(mode .. "WaterWaveSize") or T.WaterWaveSize
end

local function openHole()
	-- Roblox won't draw images (our fish) through terrain water when seen from above, so on this
	-- client only the water in the fishing area is replaced by air plus our own sea surface.
	local xs, zs = {}, {}
	for _, a in { -70, 130 } do
		for _, b in { -40, 100 } do
			local p = origin + F * a + R * CAM_SIDE * b
			table.insert(xs, p.X)
			table.insert(zs, p.Z)
		end
	end
	local lo = Vector3.new(math.min(table.unpack(xs)), -132, math.min(table.unpack(zs)))
	local hi = Vector3.new(math.max(table.unpack(xs)), WATER_Y, math.max(table.unpack(zs)))
	-- (the old terrain water is gone: the nebula sea is drawn entirely by this view)
	local size = hi - lo
	surfacePart = newPart("NebulaSurface", {
		Size = Vector3.new(size.X, 0.2, size.Z),
		CFrame = CFrame.new(Vector3.new((lo.X + hi.X) / 2, WATER_Y - 0.1, (lo.Z + hi.Z) / 2)),
		Material = Enum.Material.SmoothPlastic, -- not Glass: glass hides the fish images behind it
		Color = Color3.fromRGB(60, 34, 130),
		Transparency = 0.86,
		Reflectance = 0,
	})
	-- stardust sparkling on the surface of the nebula
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = Art.ui.glowdot
	sparkle.Shape = Enum.ParticleEmitterShape.Box
	sparkle.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	sparkle.Rate = 70
	sparkle.Lifetime = NumberRange.new(1.5, 3)
	sparkle.Speed = NumberRange.new(0.4, 1.4)
	sparkle.EmissionDirection = Enum.NormalId.Top
	sparkle.SpreadAngle = Vector2.new(30, 30)
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.45), NumberSequenceKeypoint.new(1, 0) })
	sparkle.LightEmission = 1
	sparkle.LightInfluence = 0
	sparkle.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150, 220, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 170, 240)) })
	sparkle.Parent = surfacePart
	-- low glowing mist rolling over the surface
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Shape = Enum.ParticleEmitterShape.Box
	mist.Rate = 10
	mist.Lifetime = NumberRange.new(6, 9)
	mist.Speed = NumberRange.new(0.2, 0.8)
	mist.EmissionDirection = Enum.NormalId.Top
	mist.SpreadAngle = Vector2.new(60, 60)
	mist.Rotation = NumberRange.new(0, 360)
	mist.RotSpeed = NumberRange.new(-8, 8)
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 12) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.8), NumberSequenceKeypoint.new(1, 1) })
	mist.LightEmission = 0.6
	mist.LightInfluence = 0
	mist.Color = ColorSequence.new(Color3.fromRGB(170, 110, 255), Color3.fromRGB(90, 160, 255))
	mist.Parent = surfacePart
	local edge = newPart("SeaSurfaceGlow", {
		Size = Vector3.new(size.X, 0.08, size.Z),
		CFrame = CFrame.new(Vector3.new((lo.X + hi.X) / 2, WATER_Y - 0.25, (lo.Z + hi.Z) / 2)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(120, 80, 220),
		Transparency = 0.93,
	})
	edge.Parent = surfacePart
end
local function closeHole()
	if surfacePart then
		surfacePart:Destroy()
		surfacePart = nil
	end
end
local lineParts = {}
local hud: Frame
local powerBar: Frame
local setPower: (number) -> ()
local depthLabel: TextLabel
local layerLabel: TextLabel
local hookIcons: Frame
local depthPanel: Frame
local hintLabel: TextLabel
local bannerLabel: TextLabel
local autoBadge: TextLabel

local state = "off" -- off | aim | charge | flight | swim | land
local cam = Vector2.new(30, -14)
local camTarget = cam
local hook = PIVOT
local lineLen = 0
local theta = 0
local t = 0
local chargeT = 0
local power = 0
local flightFrom = PIVOT
local flightTo = PIVOT
local cast -- the server's cast data
local holding = false
local fishes = {} -- active swimmers
local spawned = {} -- pool index -> true
local hooked = {} -- list of swimmers on the hook
local spawnClock = 0
local maxDepthSeen = 0
local lastLayer = 0
local onFinish: (({ number }) -> ())?
local onState: ((string) -> ())?
local autoMode = false
local autoTarget
local autoNextThink = 0
local sounds = {}

local SIZE_BY_RARITY = { Junk = 16, Common = 18, Uncommon = 23, Rare = 28, Epic = 36 }

---------------------------------------------------------------- drawing helpers

local function scaleK(): number
	return root.AbsoluteSize.Y / viewH
end

local function worldOf(p: Vector2): Vector3
	return origin + F * (p.X * S) - Vector3.yAxis * (p.Y * S)
end

local function planeCF(p: Vector2, rot: number?): CFrame
	-- X axis along the sea, Y up, Z toward the camera
	return CFrame.fromMatrix(worldOf(p), F, Vector3.yAxis) * CFrame.Angles(0, 0, math.rad(rot or 0))
end

local function place(part: BasePart, p: Vector2, wUnits: number, hUnits: number, rot: number?)
	part.Size = Vector3.new(wUnits * S, hUnits * S, 0.05)
	part.CFrame = planeCF(p, rot)
end

local function lerpColor(depth: number): Color3
	local L = Config.LAYERS
	if depth <= 0 then
		return L[1].color
	end
	for i, l in L do
		local mid = (l.from + l.to) / 2
		local nextL = L[i + 1]
		if not nextL then
			return l.color
		end
		local nmid = (nextL.from + nextL.to) / 2
		if depth < nmid then
			if depth <= mid then
				return l.color
			end
			return l.color:Lerp(nextL.color, (depth - mid) / (nmid - mid))
		end
	end
	return L[#L].color
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
	tick = "rbxasset://sounds/button.wav",
}

---------------------------------------------------------------- build the scene once

function newPart(name: string, props): BasePart
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

local function build()
	gui = Ui.gui("FishingView", 5)
	gui.Enabled = false
	-- transparent full-screen frame: the HUD maths (view width in sea units) uses its size
	root = Ui.frame(gui, { Name = "Root", Size = UDim2.fromScale(1, 1) })
	-- fishing HUD
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
	powerBar, setPower = Ui.meter(hud, 14, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -70), Size = UDim2.fromOffset(420, 18), Visible = false, ZIndex = 21 })
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

-- The hook, the line and the drifting sea dust (local to this player).
local function buildWorld()
	folder = Instance.new("Folder")
	folder.Name = "MyFishing"
	folder.Parent = workspace
	hookPart = newPart("Hook", { Shape = Enum.PartType.Ball, Size = Vector3.new(0.45, 0.45, 0.45), Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 214, 110), Transparency = 1 })
	local hl = Instance.new("PointLight")
	hl.Color = Color3.fromRGB(255, 210, 120)
	hl.Range = 9
	hl.Brightness = 2.2
	hl.Parent = hookPart
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(2.4, 2.4)
	bb.LightInfluence = 0
	bb.Enabled = false
	bb.Parent = hookPart
	Ui.image(bb, Art.ui.hook, { Size = UDim2.fromScale(1, 1) })
	for i = 1, 18 do
		lineParts[i] = newPart("Line", { Size = Vector3.new(0.06, 0.06, 1), Material = Enum.Material.Neon, Color = Color3.fromRGB(225, 215, 255), Transparency = 1 })
	end
	dust = newPart("Dust", { Transparency = 1, Size = Vector3.new(60, 36, 8) })
	dustFx = Instance.new("ParticleEmitter")
	dustFx.Texture = Art.ui.glowdot
	dustFx.Shape = Enum.ParticleEmitterShape.Box
	dustFx.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	dustFx.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	dustFx.Rate = 40
	dustFx.Lifetime = NumberRange.new(4, 8)
	dustFx.Speed = NumberRange.new(0.1, 0.5)
	dustFx.LightEmission = 1
	dustFx.LightInfluence = 0
	dustFx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.75), NumberSequenceKeypoint.new(1, 0) })
	dustFx.Transparency = NumberSequence.new(0.25)
	dustFx.Enabled = false
	dustFx.Parent = dust
	gasFx = Instance.new("ParticleEmitter")
	gasFx.Texture = "rbxasset://textures/particles/smoke_main.dds"
	gasFx.Shape = Enum.ParticleEmitterShape.Box
	gasFx.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	gasFx.Rate = 12
	gasFx.Lifetime = NumberRange.new(8, 12)
	gasFx.Speed = NumberRange.new(0.2, 0.7)
	gasFx.SpreadAngle = Vector2.new(180, 180)
	gasFx.Rotation = NumberRange.new(0, 360)
	gasFx.RotSpeed = NumberRange.new(-6, 6)
	gasFx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 10), NumberSequenceKeypoint.new(1, 24) })
	gasFx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.6), NumberSequenceKeypoint.new(0.7, 0.68), NumberSequenceKeypoint.new(1, 1) })
	gasFx.LightEmission = 1
	gasFx.LightInfluence = 0
	gasFx.Enabled = false
	gasFx.Parent = dust
	-- a gradient wall behind the plane, underwater only: a clean deep-sea backdrop for the side view
	backdrop = newPart("Backdrop", { Transparency = 1, Size = Vector3.new(120, BACKDROP_DEPTH, 0.2) })
	local bsg = Instance.new("SurfaceGui")
	bsg.Face = Enum.NormalId.Back
	bsg.LightInfluence = 0
	bsg.Brightness = 1
	bsg.CanvasSize = Vector2.new(64, 512)
	bsg.Parent = backdrop
	local bf = Instance.new("Frame")
	bf.BorderSizePixel = 0
	bf.BackgroundColor3 = Color3.new(1, 1, 1)
	bf.Size = UDim2.fromScale(1, 1)
	bf.Parent = bsg
	local bgr = Instance.new("UIGradient")
	bgr.Rotation = 90
	local function kp(depthUnits, c)
		return ColorSequenceKeypoint.new(math.clamp(depthUnits * S / BACKDROP_DEPTH, 0, 1), c)
	end
	local dim = 0.62
	local function d(c: Color3)
		return Color3.new(c.R * dim, c.G * dim, c.B * dim)
	end
	bgr.Color = ColorSequence.new({
		kp(0, d(WATER_TINT[1])),
		kp(30, d(WATER_TINT[1])),
		kp(100, d(WATER_TINT[2])),
		kp(185, d(WATER_TINT[3])),
		kp(315, d(WATER_TINT[4])),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 2, 12)),
	})
	bgr.Parent = bf
	-- a soft fill light that follows the view so the character and dock read at night
	local fp = newPart("Fill", { Transparency = 1, Size = Vector3.new(1, 1, 1) })
	fill = Instance.new("PointLight")
	fill.Color = Color3.fromRGB(170, 150, 255)
	fill.Range = 55
	fill.Brightness = 1.8
	fill.Shadows = false
	fill.Parent = fp
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

local function rodTipWorld(): Vector3
	local tip = rod and rod:FindFirstChild("Tip")
	if tip then
		return (tip :: BasePart).Position
	end
	return worldOf(PIVOT)
end

local function banner(text: string, color: Color3?)
	bannerLabel.Text = string.upper(text)
	bannerLabel.TextColor3 = color or Ui.CYAN
	bannerLabel.TextTransparency = 0
	local fade = TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(bannerLabel, fade, { TextTransparency = 1 }):Play()
	-- the outline fades with the text (it used to stay on screen as a dark ghost)
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

---------------------------------------------------------------- fish

local function spawnFish(entry, fromLeft: boolean, atX: number?)
	local f = Config.BY_ID[entry.id]
	local mv = Config.MOVE[f.rarity]
	local size = Config.SIZES[entry.size]
	local w = SIZE_BY_RARITY[f.rarity] * size.scale
	local viewW = root.AbsoluteSize.X / scaleK()
	local x = atX or (cam.X + (if fromLeft then -1 else 1) * (viewW / 2 + w))
	local card = newPart("Fish", { Transparency = 1 })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.LightInfluence = 0
	sg.Brightness = 1.8
	sg.CanvasSize = Vector2.new(256, 128)
	sg.Parent = card
	local img = Ui.image(sg, Art.fish[f.id], { Size = UDim2.fromScale(1, 1) })
	local rng = Random.new(entry.seed)
	local fish = {
		entry = entry,
		def = f,
		g = card,
		img = img,
		w = w,
		p = Vector2.new(x, entry.depth),
		baseY = entry.depth,
		dir = if fromLeft then 1 else -1,
		speed = mv.speed * rng:NextNumber(0.85, 1.15),
		amp = mv.amp,
		freq = mv.freq,
		phase = rng:NextNumber(0, math.pi * 2),
		dart = mv.dart,
		dartT = 0,
		nextDart = rng:NextNumber(0.6, 1.6),
		age = 0,
		rng = rng,
		life = (viewW + w * 2) / (mv.speed * 0.8) + 4,
	}
	if fish.dir < 0 then
		img.ImageRectOffset = Vector2.new(512, 0)
		img.ImageRectSize = Vector2.new(-512, 256)
	end
	table.insert(fishes, fish)
	return fish
end

local function trySpawn()
	local half = viewH / 2 + 8
	local candidates = {}
	for _, e in cast.pool do
		if not spawned[e.i] and math.abs(e.depth - cam.Y) < half then
			table.insert(candidates, e)
		end
	end
	if #candidates == 0 then
		-- recycle shallow commons so there is always something nearby
		for _, e in cast.pool do
			if math.abs(e.depth - cam.Y) < half then
				local active = false
				for _, f in fishes do
					if f.entry == e then
						active = true
					end
				end
				if not active and not e.caught then
					table.insert(candidates, e)
				end
			end
		end
	end
	if #candidates == 0 then
		return
	end
	local e = candidates[math.random(1, #candidates)]
	spawned[e.i] = true
	-- fish never come from inside the dock
	local viewW = root.AbsoluteSize.X / scaleK()
	local fromLeft = math.random() < 0.5 and (cam.X - viewW / 2) > -25
	spawnFish(e, fromLeft)
end

local function updateFish(dt: number)
	for i = #fishes, 1, -1 do
		local f = fishes[i]
		if f.isHooked then
			continue
		end
		f.age += dt
		local sp = f.speed
		if f.dart > 0 then
			f.nextDart -= dt
			if f.nextDart <= 0 then
				if f.rng:NextNumber() < f.dart then
					f.dartT = 0.35
					f.baseY += f.rng:NextNumber(-14, 14)
				end
				f.nextDart = f.rng:NextNumber(0.7, 1.6)
			end
			if f.dartT > 0 then
				f.dartT -= dt
				sp *= 2.6
			end
		end
		local x = f.p.X + f.dir * sp * dt
		local y = f.baseY + math.sin(f.age * f.freq * math.pi * 2 * 0.5 + f.phase) * f.amp
		f.p = Vector2.new(x, math.max(4, y))
		if f.age > f.life or x < -30 then
			f.g:Destroy()
			table.remove(fishes, i)
		else
			place(f.g, f.p, f.w, f.w / 2, math.cos(f.age * f.freq * math.pi + f.phase) * 8 * f.dir)
		end
	end
end

-- distance from point p to the segment a-b (the path the hook took this frame)
local function segDist(p: Vector2, a: Vector2, b: Vector2): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then
		return (p - a).Magnitude
	end
	local tt = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	return (p - (a + ab * tt)).Magnitude
end

local function checkCatch(prevHook: Vector2?)
	if not cast or #hooked >= cast.hookCap then
		return
	end
	local from = prevHook or hook
	for _, f in fishes do
		if #hooked >= cast.hookCap then
			break
		end
		-- generous: the hook catches a fish if it passes anywhere over its body
		if not f.isHooked and not f.ghost and segDist(f.p, from, hook) < C.hookRadius + f.w * 0.42 then
			f.isHooked = true
			f.entry.caught = true
			table.insert(hooked, f)
			sound(SFX.catch, 0.6, 0.9 + Config.RARITY[f.def.rarity].order * 0.12)
			local col = Config.RARITY[f.def.rarity].color
			banner((if f.entry.size >= 4 then Config.SIZES[f.entry.size].name .. " " else "") .. f.def.name .. " hooked!", col)
			refreshHookIcons()
			if #hooked >= cast.hookCap then
				hintLabel.Text = "HOOK FULL  ·  REEL IT IN"
			end
		end
	end
end

---------------------------------------------------------------- auto fish (a steady, average fisher)

local function autoThink(now: number)
	if now < autoNextThink then
		return
	end
	autoNextThink = now + 0.18 + math.random() * 0.2
	if #hooked >= cast.hookCap then
		holding = true
		return
	end
	if autoTarget and (autoTarget.isHooked or not table.find(fishes, autoTarget)) then
		autoTarget = nil
	end
	if not autoTarget then
		local best, bestD = nil, math.huge
		for _, f in fishes do
			if not f.isHooked and not f.ghost then
				local order = Config.RARITY[f.def.rarity].order
				local skip = order >= 3 and math.random() > Config.AUTO_FISH_SKILL
				local ahead = (f.p.X - hook.X) * f.dir < 0 -- still swimming toward the hook
				local d = (f.p - hook).Magnitude
				if not skip and ahead and d < bestD then
					best, bestD = f, d
				end
			end
		end
		autoTarget = best
	end
	if autoTarget then
		holding = hook.Y > autoTarget.p.Y + 3 + (math.random() - 0.5) * 6
	else
		holding = math.random() < 0.25
	end
end

---------------------------------------------------------------- per-frame

local function drawScene()
	local k = scaleK()
	local s = root.AbsoluteSize
	-- camera: a flat side view of the plane, looking at the sea point 'cam'
	local camera = workspace.CurrentCamera
	local focus = worldOf(cam)
	local dist = (viewH * S / 2) / math.tan(math.rad(FOV / 2))
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FOV
	camera.CFrame = CFrame.lookAt(focus + R * CAM_SIDE * dist, focus)
	-- the sea darkens with depth (local to this player)
	local depthHere = math.max(0, cam.Y)
	workspace.Terrain.WaterColor = if cam.Y > 4 then waterTint(depthHere) else (savedWater or WATER_TINT[1])
	if seaFog then
		local under = cam.Y > 2
		seaFog.Enabled = under
		if under then
			local tint = waterTint(depthHere)
			seaFog.TintColor = Color3.new(0.55 + tint.R * 0.6, 0.55 + tint.G * 0.6, 0.6 + tint.B * 0.5)
		end
	end
	-- drifting dust around the view while underwater
	dust.CFrame = planeCF(cam) * CFrame.new(0, 0, -6)
	do
		local wv = s.X / k * S * (dist + BACKDROP_GAP) / dist + 30
		backdrop.Size = Vector3.new(wv, BACKDROP_DEPTH, 0.2)
		backdrop.CFrame = CFrame.fromMatrix(worldOf(Vector2.new(cam.X, 0)) - Vector3.yAxis * (BACKDROP_DEPTH / 2 + 0.4) - R * CAM_SIDE * BACKDROP_GAP, F, Vector3.yAxis)
	end
	if fill then
		(fill.Parent :: BasePart).CFrame = CFrame.new(focus + R * CAM_SIDE * 14 + Vector3.yAxis * 6)
	end
	dust.Size = Vector3.new(s.X / k * S, viewH * S, 8)
	dustFx.Enabled = cam.Y > 12
	local li = Config.layerAt(depthHere)
	local dustCols = { Color3.fromRGB(120, 255, 230), Color3.fromRGB(170, 140, 255), Color3.fromRGB(255, 120, 210), Color3.fromRGB(255, 150, 90) }
	dustFx.Color = ColorSequence.new(dustCols[li])
	if gasFx then
		gasFx.Enabled = cam.Y > 3
		local gasCols = { Color3.fromRGB(170, 120, 255), Color3.fromRGB(110, 90, 255), Color3.fromRGB(220, 90, 220), Color3.fromRGB(120, 50, 160) }
		gasFx.Color = ColorSequence.new(gasCols[li], gasCols[math.min(li + 1, #gasCols)])
	end
	-- line: rod tip to hook with a little sag
	local out = state ~= "aim" and state ~= "charge" and state ~= "waiting"
	local a = rodTipWorld()
	local b = worldOf(hook)
	local slack = if state == "swim" then 0 else 1.5
	local ctrl = (a + b) / 2 - Vector3.yAxis * (1 + slack)
	local prev = a
	for i, seg in lineParts do
		local tt = i / #lineParts
		local p = a:Lerp(ctrl, tt):Lerp(ctrl:Lerp(b, tt), tt)
		local len = (p - prev).Magnitude
		seg.Size = Vector3.new(0.06, 0.06, math.max(0.01, len))
		if len > 0.001 then
			seg.CFrame = CFrame.lookAt((p + prev) / 2, p)
		end
		seg.Transparency = if out then 0.1 else 1
		prev = p
	end
	hookPart.CFrame = CFrame.new(b)
	hookPart.Transparency = if out then 0 else 1
	local hb = hookPart:FindFirstChildOfClass("BillboardGui")
	if hb then
		hb.Enabled = out
	end
	-- fish on the hook dangle below it
	for i, f in hooked do
		f.p = hook + Vector2.new(0, 3 + i * f.w * 0.28)
		place(f.g, f.p, f.w, f.w / 2, 90 * f.dir + math.sin(os.clock() * 6 + i) * 10)
	end
	depthPanel.Visible = state == "flight" or state == "swim" or state == "land"
end

local function finishCast()
	state = "land"
	local list = {}
	for _, f in hooked do
		table.insert(list, f.entry.i)
	end
	local from = hook
	local tw = 0
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		tw += dt / 0.45
		hook = from:Lerp(PIVOT, math.min(1, tw))
		if tw >= 1 then
			conn:Disconnect()
			for _, f in hooked do
				f.g:Destroy()
				local i = table.find(fishes, f)
				if i then
					table.remove(fishes, i)
				end
			end
			for _, f in fishes do
				f.g:Destroy()
			end
			table.clear(fishes)
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
	end)
end

local function ambientFish(dt: number)
	if not cast then
		updateFish(dt)
		return
	end
	spawnClock -= dt
	if spawnClock <= 0 then
		spawnClock = 0.5 + math.random() * 0.5
		local live = 0
		for _, f in fishes do
			if not f.ghost then
				live += 1
			end
		end
		if live < 7 then
			trySpawn()
		end
	end
	updateFish(dt)
end

local function step(dt: number)
	local now = os.clock()
	if state == "charge" then
		chargeT += dt
		power = 1
		camTarget = AIM_CAM
		ambientFish(dt)
	elseif state == "flight" then
		t += dt / C.flightTime
		local tt = math.min(1, t)
		hook = flightFrom:Lerp(flightTo, tt) - Vector2.new(0, math.sin(tt * math.pi) * (18 + power * 22))
		camTarget = hook -- the camera follows the hook from the moment it leaves the rod
		ambientFish(dt)
		if tt >= 1 then
			state = "swim"
			sound(SFX.splash, 0.5)
			local d = hook - PIVOT
			lineLen = d.Magnitude
			theta = math.atan2(d.X, d.Y)
			hintLabel.Text = if autoMode then "" else "HOLD TO REEL  ·  TAP TO ADJUST"
			if onState then
				onState("swim")
			end
		end
	elseif state == "swim" then
		if autoMode then
			autoThink(now)
		end
		theta -= C.swing * (cast.sink or 1) * math.sin(theta) * dt -- Hook Modification: sinks faster
		lineLen -= C.passiveReel * dt
		if cast.maxLen and lineLen > cast.maxLen then
			-- a long cast lands past the Tether's reach: the line draws back to its length (keeps depth fair)
			lineLen -= (lineLen - cast.maxLen) * math.min(1, dt * 1.1)
		end
		if holding then
			lineLen -= cast.reel * dt
		end
		local prevHook = hook
		hook = PIVOT + Vector2.new(math.sin(theta), math.cos(theta)) * lineLen
		local depth = math.max(0, hook.Y)
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
		camTarget = Vector2.new(math.max(40, hook.X - 6), math.max(-24, hook.Y))
		spawnClock -= dt
		if spawnClock <= 0 then
			spawnClock = 0.55 + math.random() * 0.5
			if #fishes - #hooked < 6 then
				trySpawn()
			end
		end
		updateFish(dt)
		checkCatch(prevHook)
		if lineLen <= C.minLine or (hook.Y < 0.5 and maxDepthSeen > 8) or now - (cast.t0 or now) > C.maxCastSeconds then
			finishCast()
		end
	elseif state == "land" then
		updateFish(dt)
	else
		camTarget = AIM_CAM
		ambientFish(dt)
	end
	local wantH = if state == "swim" or state == "land" or state == "flight" then SWIM_VIEW_H else AIM_VIEW_H
	viewH += (wantH - viewH) * (1 - math.exp(-dt * 2.5))
	cam = cam:Lerp(camTarget, 1 - math.exp(-dt * 4))
	drawScene()
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
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	F = (CFrame.Angles(0, math.rad(ctx.facing or 0), 0) * CFrame.new(0, 0, -1)).Position
	R = F:Cross(Vector3.yAxis).Unit
	if not folder or not folder.Parent then
		table.clear(lineParts)
		buildWorld()
	end
	if character and not character:FindFirstChild("FishingRod") then
		attachRod(character)
	end
	-- sea (0, 0) sits on the water just in front of the player
	local base = if hrp then hrp.Position + F * 2.4 else Vector3.zero
	origin = Vector3.new(base.X, WATER_Y, base.Z) - F * (PIVOT.X * S)
	savedWater = savedWater or workspace.Terrain.WaterColor
	savedExposure = savedExposure or game.Lighting.ExposureCompensation
	game.Lighting.ExposureCompensation = savedExposure + 0.55
	closeHole()
	openHole()
	setSea("Fish")
	if not seaFog then
		seaFog = Instance.new("ColorCorrectionEffect")
		seaFog.Name = "FishingSeaTint"
		seaFog.Enabled = false
		seaFog.Parent = game:GetService("Lighting")
	end
	-- bring the black hole into the background of this view
	local world = workspace:FindFirstChild("World")
	local sky = world and world:FindFirstChild("Sky")
	blackHolePart = sky and sky:FindFirstChild("BlackHole") :: BasePart?
	if blackHolePart then
		local bbg = blackHolePart:FindFirstChildOfClass("BillboardGui")
		blackHoleSaved = blackHoleSaved or { cf = blackHolePart.CFrame, size = bbg and bbg.Size }
		blackHolePart.CFrame = CFrame.new(origin - R * CAM_SIDE * 1200 + F * 260 + Vector3.yAxis * 250)
		if bbg then
			bbg.Size = UDim2.new(620, 0, 620, 0)
			bbg.Enabled = true -- hidden in the lobby sky, shown behind the fishing view
		end
	end
	if backdrop then
		(backdrop:FindFirstChildOfClass("SurfaceGui") :: SurfaceGui).Enabled = true
	end
	if fill then
		fill.Enabled = true
	end
	gui.Enabled = true
	state = "aim"
	cam = AIM_CAM
	viewH = AIM_VIEW_H
	hook = PIVOT
	hintLabel.Text = if autoMode then "" else "TAP TO CAST"
	powerBar.Visible = false
	depthLabel.Text = "0 M"
	layerLabel.Text = string.upper(Config.LAYERS[1].name)
	refreshHookIcons()
	drawScene()
end

function View.close()
	gui.Enabled = false
	closeHole()
	setSea("Lobby")
	if seaFog then
		seaFog.Enabled = false
	end
	state = "off"
	for _, f in fishes do
		f.g:Destroy()
	end
	table.clear(fishes)
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
	if dustFx then
		dustFx.Enabled = false
	end
	if gasFx then
		gasFx.Enabled = false
	end
	if backdrop then
		(backdrop:FindFirstChildOfClass("SurfaceGui") :: SurfaceGui).Enabled = false
	end
	if fill then
		fill.Enabled = false
	end
	if rod then
		rod:Destroy()
		rod = nil
	end
	if savedWater then
		workspace.Terrain.WaterColor = savedWater
	end
	if savedExposure then
		game.Lighting.ExposureCompensation = savedExposure
	end
	if blackHolePart and blackHoleSaved then
		blackHolePart.CFrame = blackHoleSaved.cf
		local bbg = blackHolePart:FindFirstChildOfClass("BillboardGui")
		if bbg and blackHoleSaved.size then
			bbg.Size = blackHoleSaved.size
		end
		if bbg then
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
		state = "charge" -- a tap casts at full power (no power bar)
		chargeT = 0
	elseif state == "swim" and not autoMode then
		holding = true
		lineLen -= C.tapReel * 0.35
	end
end

function View.release(): number?
	if state == "charge" then
		powerBar.Visible = false
		local p = 1
		state = "waiting"
		return p
	elseif state == "swim" and not autoMode then
		holding = false
		lineLen -= C.tapReel * 0.65
	end
	return nil
end

-- The server approved the cast: launch the hook.
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
	power = p
	local dist = math.max(-PIVOT.Y + 8, cast.maxLen * p)
	local reach = math.max(math.sqrt(math.max(0, dist * dist - PIVOT.Y * PIVOT.Y)), cast.reach or C.minReach or 0)
	flightFrom = PIVOT
	flightTo = Vector2.new(PIVOT.X + reach, 0)
	t = 0
	state = "flight"
	sound(SFX.cast, 0.6)
	hintLabel.Text = ""
	refreshHookIcons()
	if onState then
		onState("flight")
	end
end

-- The next cast is ready (fetched while you aim): its fish start swimming now.
function View.prepare(serverCast)
	cast = serverCast
	table.clear(spawned)
	for i = #fishes, 1, -1 do
		local f = fishes[i]
		if not f.isHooked then
			f.g:Destroy()
			table.remove(fishes, i)
		end
	end
	-- first time in: fill the view straight away instead of waiting for fish to swim in
	local live = 0
	for _, f in fishes do
		if f.g.Parent then
			live += 1
		end
	end
	if live < 3 and cast.pool then
		local viewW = root.AbsoluteSize.X / scaleK()
		local half = viewH / 2
		local list = {}
		for _, e in cast.pool do
			if math.abs(e.depth - cam.Y) < half then
				table.insert(list, e)
			end
		end
		for k = 1, math.min(6, #list) do
			local e = table.remove(list, math.random(1, #list))
			spawned[e.i] = true
			spawnFish(e, math.random() < 0.5, math.max(12, cam.X + (math.random() - 0.3) * viewW * 0.8))
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
