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

local Players = game:GetService("Players")
local Shared = ReplicatedStorage:WaitForChild("FishInSpace")
local Config = require(Shared:WaitForChild("Config"))
local Art = require(Shared:WaitForChild("Art"))
local Ui = require(script.Parent:WaitForChild("Ui"))
local SeaDecor = require(script.Parent:WaitForChild("SeaDecor"))

local View = {}

local AIM_VIEW_H = 62 -- sea units visible top to bottom while aiming: a close shot of you and your rod
local SWIM_VIEW_H = 290 -- while the hook is out (wide: you see the whole cast and fish coming)
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
local BACKDROP_DEPTH = 650 -- studs of sea it covers
local C = Config.CAST
local PIVOT = C.rodTip

local gui: ScreenGui
local root: Frame
local folder: Folder -- this player's local fishing parts (hook, line, fish, dust)
local origin = Vector3.zero -- the world point for sea (0, 0)
local F = Vector3.new(0, 0, -1) -- out to sea
local R = Vector3.new(1, 0, 0) -- toward the camera
local character: Model?
local rod: Instance?
local hookPart: BasePart
local hookCard: BasePart -- the hook picture (see buildWorld)
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
	for _, a in { -70, 260 } do
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
local goldLine = false -- every fish caught: the line turns gold
local lineColor = Color3.fromRGB(225, 215, 255) -- God Rod / VIP / Starter Pack colors (Config.LINE_COLORS)
local boostLabel: TextLabel
local lastGateMsg = 0
local nameTags = {}
local hud: Frame
local powerBar: Frame
local setPower: (number) -> ()
local depthLabel: TextLabel
local layerLabel: TextLabel
local hookIcons: Frame
local depthPanel: Frame
local hintLabel: TextLabel
local fight = nil -- the rare-fish fight in progress (see startFight)
local fightHold = false
local fightPanel: ImageLabel
local fightTitle: TextLabel
local fightZone: Frame
local fightFish: ImageLabel
local setFightProgress: (number) -> ()
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
local spooled = false -- the line has finished paying out to its full length this cast
local lastLayer = 0
local onFinish: (({ number }) -> ())?
local onState: ((string) -> ())?
local onLost: ((number, any) -> ())? -- a Rare/Epic broke free (pool index, fish def): the "keep it" offer
local shark = nil -- the space shark hunting your catch (see updateShark)
local sharkRolled = false -- (one roll per cast)
local autoMode = false
local autoTargets = { Common = true, Uncommon = true, Rare = true, Epic = true } -- what Auto Fish goes after
local autoTarget
local autoNextThink = 0
local sounds = {}

local SIZE_BY_RARITY = { Junk = 16, Common = 18, Uncommon = 25, Rare = 34, Epic = 50 }

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

-- 3D fish models (ReplicatedStorage.FishInSpace.FishModels): each model's pivot faces its head
local FishModels = game:GetService("ReplicatedStorage"):WaitForChild("FishInSpace"):WaitForChild("FishModels", 10)
local FISH_YAW = 22 -- degrees the head turns toward the camera, so you see a bit of the face (3/4 view)

local function placeFish(f, rot: number)
	if f.model then
		local yaw = if f.dir > 0 then -90 - FISH_YAW else 90 + FISH_YAW
		f.model:PivotTo(planeCF(f.p, rot * 0.6) * CFrame.Angles(0, math.rad(yaw), 0))
	else
		place(f.g, f.p, f.w, f.w / 2, rot)
	end
end

-- fade a model fish in (a = 0..1), keeping each part's own see-through amount
local function setFishAlpha(f, a: number)
	for _, pt in f.mparts do
		pt[1].Transparency = 1 - (1 - pt[2]) * a
	end
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

-- sounds come from the shared list (FishClient.Sounds): soft, warm and all through the SFX group
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local function sound(name: string, _vol: number?, speed: number?)
	Sounds.play(name, { pitch = speed or 1 })
end
local SFX = { cast = "cast", splash = "splash", catch = "catch", tick = "click" }
_ = sounds

-- game feel: a short camera shake, a tiny impact pause ("hit-stop") and a moment of slow motion for the big
-- beats (a bite, a rare fish thrashing, the catch). The Screen Shake setting turns all three off.
local Settings = require(script.Parent:WaitForChild("Settings"))
local shakeAmp = 0 -- camera shake strength, as a fraction of the view height (decays quickly)
local hitStop = 0 -- seconds left of the impact pause
local slowMo = 0 -- seconds left of slow motion
-- a controller rumble for the big moments (gamepads only; phones don't expose vibration to games)
local HapticService = game:GetService("HapticService")
local function rumble(strength: number, seconds: number)
	pcall(function()
		local dev = Enum.UserInputType.Gamepad1
		if HapticService:IsVibrationSupported(dev) and HapticService:IsMotorSupported(dev, Enum.VibrationMotor.Large) then
			HapticService:SetMotor(dev, Enum.VibrationMotor.Large, strength)
			task.delay(seconds, function()
				pcall(HapticService.SetMotor, HapticService, dev, Enum.VibrationMotor.Large, 0)
			end)
		end
	end)
end
local function kick(amp: number, freeze: number?, slow: number?)
	if Settings.get("shake") == false then
		return
	end
	shakeAmp = math.max(shakeAmp, amp)
	hitStop = math.max(hitStop, freeze or 0)
	slowMo = math.max(slowMo, slow or 0)
	if amp >= 0.008 then
		rumble(math.clamp(amp * 40, 0.3, 0.8), 0.12)
	end
end

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
	-- (bottom left: the right side has Leave, Auto and the Auto Fish picker, and the quest card is top left)
	depthPanel = Ui.panel(hud, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -24), Size = UDim2.fromOffset(190, 96), ZIndex = 20 })
	Ui.label(depthPanel, { Text = "DEPTH", Font = Ui.TECH, TextSize = 14, TextColor3 = Ui.MUTED, Position = UDim2.fromOffset(22, 12), Size = UDim2.fromOffset(140, 16), ZIndex = 21 })
	depthLabel = Ui.label(depthPanel, { Text = "0 M", Font = Ui.TITLE, TextSize = 26, Position = UDim2.fromOffset(22, 30), Size = UDim2.fromOffset(150, 30), ZIndex = 21 })
	layerLabel = Ui.label(depthPanel, { Text = "", Font = Ui.TECH, TextSize = 14, TextColor3 = Ui.CYAN, Position = UDim2.fromOffset(22, 62), Size = UDim2.fromOffset(160, 18), ZIndex = 21 })
	boostLabel = Ui.label(depthPanel, { Text = "RARE BOOST", Font = Ui.TECH, TextSize = 15, TextColor3 = Ui.GOLD, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -6), Size = UDim2.new(1, 0, 0, 20), Visible = false, ZIndex = 21 })
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
	-- the rare-fish fight panel (bottom centre)
	fightPanel = Ui.panel(hud, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -130), Size = UDim2.fromOffset(540, 150), Visible = false, ZIndex = 30 })
	fightTitle = Ui.label(fightPanel, { Text = "", Font = Ui.TITLE, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 24), ZIndex = 31 })
	local track = Ui.frame(fightPanel, { Name = "Track", BackgroundTransparency = 0.25, BackgroundColor3 = Color3.fromRGB(16, 10, 40), Position = UDim2.fromOffset(34, 52), Size = UDim2.new(1, -68, 0, 38), ZIndex = 31 })
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 8)
	tc.Parent = track
	local ts = Instance.new("UIStroke")
	ts.Color = Ui.PURPLE
	ts.Transparency = 0.3
	ts.Parent = track
	fightZone = Ui.frame(track, { Name = "Zone", BackgroundTransparency = 0.45, BackgroundColor3 = Ui.GREEN, Size = UDim2.fromScale(0.3, 1), ZIndex = 32 })
	local zc = Instance.new("UICorner")
	zc.CornerRadius = UDim.new(0, 8)
	zc.Parent = fightZone
	fightFish = Ui.image(track, "", { Name = "Fish", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(56, 34), ZIndex = 33 })
	local _, setP = Ui.meter(fightPanel, 20, { Position = UDim2.fromOffset(34, 100), Size = UDim2.new(1, -68, 0, 12), ZIndex = 31 }, Ui.GREEN)
	setFightProgress = setP
	Ui.label(fightPanel, { Text = "HOLD TO PULL  ·  LET GO TO EASE OFF  ·  KEEP THE FISH IN THE GREEN", Font = Ui.TECH, TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 120), Size = UDim2.new(1, 0, 0, 18), ZIndex = 31 })
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
	bb.SizeOffset = Vector2.new(0, -0.3) -- the line ties on at the J's eye, near the top of the picture
	bb.LightInfluence = 0
	bb.Enabled = false
	bb.Parent = hookPart
	Ui.image(bb, Art.ui.hook, { Size = UDim2.fromScale(1, 1) })
	-- (the billboard above stays off: it trails behind the line during a fast cast. The hook is this flat card
	-- in the sea's plane instead, moved in the same frame as the line, so it always sits right on the line's end.)
	hookCard = newPart("HookCard", { Transparency = 1, Size = Vector3.new(2.4, 2.4, 0.05) })
	local hsg = Instance.new("SurfaceGui")
	hsg.Face = Enum.NormalId.Back -- (Back faces the camera, like the fish cards)
	hsg.LightInfluence = 0
	hsg.Brightness = 1.6
	hsg.CanvasSize = Vector2.new(128, 128)
	hsg.Enabled = false
	hsg.Parent = hookCard
	Ui.image(hsg, Art.ui.hook, { Size = UDim2.fromScale(1, 1) })
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
		kp(120, d(WATER_TINT[1])),
		kp(400, d(WATER_TINT[2])),
		kp(740, d(WATER_TINT[3])),
		kp(1260, d(WATER_TINT[4])),
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

-- The character's rod (put on their back by the server) moves to their hands while fishing.
-- RodPose tells the server: "hold" when the view opens, "cast" on each cast, "back" when it closes.
local RodPose = Shared:WaitForChild("Remotes"):WaitForChild("RodPose") :: RemoteEvent
-- rod swing cues: "windup" when you start a cast (rod goes back over the shoulder), "cast" at launch (whip)
local function rodCue(kind: string)
	RodPose:FireServer(kind)
	local me = Players.LocalPlayer
	if me then
		me:SetAttribute(if kind == "cast" then "LocalCastAt" else "LocalWindAt", os.clock())
	end
end

local function attachRod(char: Model)
	RodPose:FireServer("hold")
	rod = char:WaitForChild("FishingRod", 3)
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
		Ui.image(hookIcons, Art.icon.hook, { Size = UDim2.fromOffset(20, 20), ImageColor3 = if i <= #hooked then Color3.new(1, 1, 1) else Color3.fromRGB(90, 84, 120), ImageTransparency = if i <= #hooked then 0 else 0.4, ZIndex = 21, LayoutOrder = i })
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
	sg.Enabled = false
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
		speed = mv.speed * rng:NextNumber(0.85, 1.15) * 0.55, -- fish patrol around a home spot, faster for rarer fish
		drift = (mv.drift or 0) * rng:NextNumber(0.8, 1.2), -- parked fish sway this far around their spot
		sway = (mv.sway or 0.3) * rng:NextNumber(0.85, 1.15),
		home = atX or (cam.X + (if fromLeft then -1 else 1) * viewW * 0.25),
		range = rng:NextNumber(30, 60),
		amp = mv.amp,
		freq = mv.freq,
		phase = rng:NextNumber(0, math.pi * 2),
		dart = mv.dart,
		dartT = 0,
		nextDart = rng:NextNumber(0.6, 1.6),
		age = 0,
		rng = rng,
		life = math.huge,
		sg = sg,
	}
	local src = FishModels and FishModels:FindFirstChild(entry.id)
	if src then
		-- the 3D model, as long as the old picture was wide
		local m = src:Clone()
		local len = m:GetAttribute("Length") or 2
		m:ScaleTo(m:GetScale() * (w * S) / len)
		local mparts = {}
		for _, pt in m:GetDescendants() do
			if pt:IsA("BasePart") then
				pt.CastShadow = false
				table.insert(mparts, { pt, pt.Transparency })
			end
		end
		-- no aura while swimming: it only appears once you pull the fish out
		-- but while a Rare Boost is on, the fish it brings in sparkle so you can see it working
		local boosted = cast and cast.boost and ((entry.layer == 1 and f.rarity == "Uncommon") or (entry.layer > 1 and f.rarity == Config.TOP_RARITY[entry.layer]))
		local body = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
		if boosted and body then
			local sp = Instance.new("ParticleEmitter")
			sp.Name = "BoostSparkle"
			sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sp.Color = ColorSequence.new(Ui.GOLD)
			sp.LightEmission = 1
			sp.Size = NumberSequence.new(w * S * 0.12)
			sp.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			sp.Lifetime = NumberRange.new(0.5, 0.9)
			sp.Rate = 8
			sp.Speed = NumberRange.new(0.5, 1.5)
			sp.SpreadAngle = Vector2.new(180, 180)
			sp.Parent = body
		end
		fish.model = m
		fish.mparts = mparts
		fish.fade = 1
		img.ImageTransparency = 1
	end
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
		if not spawned[e.i] and math.abs(e.depth - cam.Y) < half and ((Config.LAYERS[e.layer] and Config.LAYERS[e.layer].out) or 0) < cam.X + half * 1.6 then
			table.insert(candidates, e)
		end
	end
	if #candidates == 0 then
		-- recycle shallow commons so there is always something nearby
		for _, e in cast.pool do
			if math.abs(e.depth - cam.Y) < half and ((Config.LAYERS[e.layer] and Config.LAYERS[e.layer].out) or 0) < cam.X + half * 1.6 then
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
	local out = (Config.LAYERS[e.layer] and Config.LAYERS[e.layer].out) or 30
	local fromLeft = math.random() < 0.5 and (cam.X - viewW / 2) > math.max(-25, out)
	if math.random() < 0.85 then
		-- most fish fade in already inside the view, so the sea around the hook is full right away
		-- around the hook's column, so a straight drop and reel passes through them
		local lo = math.max(cam.X - viewW * 0.45, out, hook.X - 90)
		local hi = math.min(cam.X + viewW * 0.45, math.max(hook.X, out) + 110)
		if hi > lo then
			local f = spawnFish(e, math.random() < 0.5, lo + math.random() * (hi - lo))
			if f.model then
				f.fade = 0
			else
				f.img.ImageTransparency = 1
				game:GetService("TweenService"):Create(f.img, TweenInfo.new(0.6), { ImageTransparency = 0 }):Play()
			end
			return
		end
	end
	spawnFish(e, fromLeft)
end

local function updateFish(dt: number)
	local viewHalfW = (root.AbsoluteSize.X / scaleK()) / 2
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
		local fOut = (Config.LAYERS[f.entry.layer] and Config.LAYERS[f.entry.layer].out) or 0
		local turn = nil
		if f.dir < 0 and (f.p.X < fOut or (f.home and f.p.X < f.home - f.range)) then
			turn = 1 -- deep fish keep to their own water further out; every fish patrols around its home
		elseif f.dir > 0 and f.home and f.p.X > f.home + f.range then
			turn = -1
		end
		if turn then
			f.dir = turn
			if turn > 0 then
				f.img.ImageRectOffset = Vector2.zero
				f.img.ImageRectSize = Vector2.zero
			else
				f.img.ImageRectOffset = Vector2.new(512, 0)
				f.img.ImageRectSize = Vector2.new(-512, 256)
			end
		end
		f.baseY = math.clamp(f.baseY, f.entry.depth - 20, f.entry.depth + 20)
		local x
		if f.static then
			-- parked fish sway back and forth around their spot and turn to face the way they're going
			x = f.home + math.sin(f.age * f.sway * math.pi * 2 + f.phase) * f.drift
			local vx = x - f.p.X
			if math.abs(vx) > 1e-3 and (vx > 0) ~= (f.dir > 0) then
				f.dir = if vx > 0 then 1 else -1
				if f.dir > 0 then
					f.img.ImageRectOffset = Vector2.zero
					f.img.ImageRectSize = Vector2.zero
				else
					f.img.ImageRectOffset = Vector2.new(512, 0)
					f.img.ImageRectSize = Vector2.new(-512, 256)
				end
			end
		else
			x = f.p.X + f.dir * sp * dt
		end
		local y = f.baseY + math.sin(f.age * f.freq * math.pi * 2 * 0.5 + f.phase) * f.amp
		f.p = Vector2.new(x, math.max(6 + f.w * 0.3, y)) -- always fully under the surface
		-- the whole sea is always there; only the fish near the camera are drawn
		local onScreen = math.abs(f.p.X - cam.X) < viewHalfW + f.w and math.abs(f.p.Y - cam.Y) < viewH / 2 + f.w
		if f.model then
			local want = if onScreen then f.g else nil
			if f.model.Parent ~= want then
				f.model.Parent = want
			end
			if f.fade < 1 then
				f.fade = math.min(1, f.fade + dt / 1.2)
				setFishAlpha(f, f.fade)
			end
		elseif f.sg.Enabled ~= onScreen then
			f.sg.Enabled = onScreen
		end
		if onScreen then
			placeFish(f, math.cos(f.age * f.freq * math.pi + f.phase) * 8 * f.dir)
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

---------------------------------------------------------------- the rare-fish fight

local lostInARow: { [string]: number } = {} -- per rarity, for Config.FIGHT_COMFORT

local function startFight(f)
	local P = Config.FIGHT[f.def.rarity]
	local comfort = 1 + Config.FIGHT_COMFORT.perLoss * math.min(lostInARow[f.def.rarity] or 0, Config.FIGHT_COMFORT.max)
	local zoneW = math.min(0.6, P.zone * (cast.fightZone or 1) * comfort)
	fight = { f = f, P = P, zoneW = zoneW, zone = 0.5 - zoneW / 2, zoneV = 0, fishX = 0.5, target = 0.5, nextMove = 0.4, progress = P.start, t = 0, outside = 0 }
	if P.surge then
		fight.nextSurge = P.surge.every[1] + math.random() * (P.surge.every[2] - P.surge.every[1])
	end
	kick(0.014, 0.08) -- the bite: a jolt and a split-second pause
	f.isHooked = true -- (so nothing else touches it while you fight it)
	f.fighting = true
	state = "fight"
	holding = false
	fightHold = false
	local col = Config.RARITY[f.def.rarity].color
	fightTitle.Text = string.upper((if f.entry.size >= 4 then Config.SIZES[f.entry.size].name .. " " else "") .. f.def.name) .. " IS FIGHTING!"
	fightTitle.TextColor3 = col
	fightFish.Image = Art.fish[f.def.id] or ""
	fightZone.Size = UDim2.fromScale(zoneW, 1)
	fightZone.BackgroundColor3 = Ui.GREEN
	fightPanel.Visible = true
	hintLabel.Text = ""
	sound(SFX.catch, 0.6, 0.8)
	Sounds.play("sparkle", { pitch = if f.def.rarity == "Epic" then 0.9 else 1 })
	banner("A " .. string.upper(f.def.rarity) .. " BIT! REEL IT IN!", col)
end

local function endFight(won: boolean)
	local F = fight
	fight = nil
	fightPanel.Visible = false
	state = "swim"
	holding = false
	fightHold = false
	local f = F.f
	f.fighting = nil
	local col = Config.RARITY[f.def.rarity].color
	fightZone.BackgroundColor3 = Ui.GREEN
	if won then
		f.entry.caught = true
		table.insert(hooked, f)
		lostInARow[f.def.rarity] = 0
		Sounds.play("sparkle", { pitch = 1.2 })
		sound(SFX.splash, 0.6, 0.9)
		kick(0.018, 0.1, 0.45) -- the landing: a big jolt, a pause, then a beat of slow motion
		local grade = ""
		for _, g in Config.FIGHT_GRADES do
			if F.outside <= g.maxOutside then
				grade = g.name .. "!  "
				break
			end
		end
		banner(grade .. (if f.entry.size >= 4 then Config.SIZES[f.entry.size].name .. " " else "") .. f.def.name .. " caught!", col)
		refreshHookIcons()
		hintLabel.Text = if autoMode then "" elseif #hooked >= cast.hookCap then "HOOK FULL  ·  REEL IT IN" else "HOLD TO REEL  ·  TAP TO ADJUST"
	else
		-- it breaks free and bolts
		f.isHooked = false
		f.ghost = true
		f.static = false
		f.dir = if f.p.X >= hook.X then 1 else -1
		f.baseY = f.p.Y
		f.dartT = 1.4
		f.speed = math.max(f.speed, 30)
		lostInARow[f.def.rarity] = (lostInARow[f.def.rarity] or 0) + 1
		sound(SFX.splash, 0.6, 1.3)
		kick(0.01)
		banner(f.def.name .. " got away!", Color3.fromRGB(255, 110, 110))
		if onLost and not autoMode then
			onLost(f.entry.i, f.def)
		end
		hintLabel.Text = if autoMode then "" else "HOLD TO REEL  ·  TAP TO ADJUST"
		task.delay(3, function()
			f.ghost = nil
		end)
	end
end

local function updateFight(dt: number)
	local F = fight
	local P = F.P
	F.t += dt
	-- the fish darts about along the bar
	F.nextMove -= dt
	if F.nextMove <= 0 then
		F.nextMove = P.calm[1] + math.random() * (P.calm[2] - P.calm[1])
		if math.random() < P.dart then
			local from = F.fishX
			F.target = if F.fishX < 0.5 then 0.85 + math.random() * 0.15 else math.random() * 0.15 -- a big dash to the far side
			kick(0.004) -- you feel it yank the line
			if P.feint and math.random() < P.feint then
				F.feintBack = from -- a fake-out: partway there it snaps back
				F.feintT = 0.22
			end
		else
			F.target = math.clamp(F.fishX + (math.random() - 0.5) * 0.6, 0.03, 0.97)
		end
	end
	if F.feintT then
		F.feintT -= dt
		if F.feintT <= 0 then
			F.target = math.clamp(F.feintBack, 0.03, 0.97)
			F.feintT, F.feintBack = nil, nil
		end
	end
	-- Epic surges: the bar flashes, then the fish thrashes much faster for a moment
	local speed = P.speed
	if P.surge then
		F.nextSurge -= dt
		if F.nextSurge <= 0 then
			F.surgeT = P.surge.time
			F.nextSurge = P.surge.time + P.surge.every[1] + math.random() * (P.surge.every[2] - P.surge.every[1])
			kick(0.009)
		end
		if F.surgeT then
			F.surgeT -= dt
			speed *= P.surge.mult
			if F.surgeT <= 0 then
				F.surgeT = nil
			end
		end
		local warning = not F.surgeT and F.nextSurge <= P.surge.warn
		fightZone.BackgroundColor3 = if F.surgeT then Ui.RED elseif warning then Ui.GOLD else Ui.GREEN
	end
	F.fishX += (F.target - F.fishX) * (1 - math.exp(-dt * speed * 4))
	local fx = math.clamp(F.fishX + math.sin(F.t * 13) * 0.012, 0, 1)
	-- your catch zone: hold to push it right, let go and it drifts back left
	local hold = fightHold
	if autoMode then
		-- Auto Fish plays it like a good player: it reacts quickly and looks a little ahead of where the green
		-- zone is drifting. Simulated: wins ~94% of Rare fights and ~82% of Epic fights.
		F.autoT = (F.autoT or 0) - dt
		if F.autoT <= 0 then
			F.autoT = 0.1 + math.random() * 0.1
			F.autoHold = fx > F.zone + F.zoneV * 0.2 + F.zoneW * 0.5 + (math.random() - 0.5) * 0.1
		end
		hold = F.autoHold
	end
	F.zoneV = math.clamp(F.zoneV + (if hold then P.pull else -P.pull * 0.9) * dt, -1.1, 1.1)
	F.zone += F.zoneV * dt
	if F.zone < 0 then
		F.zone = 0
		F.zoneV = math.abs(F.zoneV) * 0.25
	elseif F.zone > 1 - F.zoneW then
		F.zone = 1 - F.zoneW
		F.zoneV = -math.abs(F.zoneV) * 0.25
	end
	local inside = fx >= F.zone and fx <= F.zone + F.zoneW
	if not inside then
		F.outside += dt
	end
	F.progress = math.clamp(F.progress + (if inside then P.gain else -P.drain) * dt, 0, 1)
	fightZone.Position = UDim2.fromScale(F.zone, 0)
	fightZone.BackgroundTransparency = if inside then 0.3 else 0.65
	fightFish.Position = UDim2.fromScale(fx, 0.5)
	fightFish.Rotation = math.sin(F.t * 16) * 12
	setFightProgress(F.progress)
	-- the fish thrashes on the line by the hook
	local f = F.f
	f.p = hook + Vector2.new((fx - 0.5) * 24, 6 + math.sin(F.t * 9) * 3)
	if f.model and f.model.Parent ~= f.g then
		f.model.Parent = f.g
	end
	placeFish(f, 90 * f.dir + math.sin(F.t * 14) * 30)
	if F.progress >= 1 then
		endFight(true)
	elseif F.progress <= 0 then
		endFight(false)
	end
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
		local tooRare = Config.RARITY[f.def.rarity].order > (cast.baitMax or 99)
		if tooRare and not f.isHooked and not f.ghost and segDist(f.p, from, hook) < C.hookRadius + f.w * 0.42 then
			-- Better Bait decides what bites: this one just swims past
			if os.clock() - lastGateMsg > 2.5 then
				lastGateMsg = os.clock()
				local need = Config.UPGRADES.lure.names[math.clamp(Config.RARITY[f.def.rarity].order, 1, #Config.UPGRADES.lure.names)]
				banner(("Bait too weak for %s (needs %s)"):format(f.def.name, need), Color3.fromRGB(255, 120, 120))
			end
		elseif not f.isHooked and not f.ghost and segDist(f.p, from, hook) < C.hookRadius + f.w * 0.42 then
			if Config.FIGHT[f.def.rarity] then
				startFight(f) -- Rare and Epic fish fight back
				return
			end
			f.isHooked = true
			f.entry.caught = true
			table.insert(hooked, f)
			sound(SFX.catch, 0.6, 0.9 + Config.RARITY[f.def.rarity].order * 0.08) -- rarer fish pop a little higher
			if Config.RARITY[f.def.rarity].order >= 3 then
				Sounds.play("sparkle", { pitch = if f.def.rarity == "Epic" then 0.9 else 1 }) -- a rare one: the harp
				kick(0.008, 0.05)
			else
				kick(0.003) -- a little tug on every bite
			end
			local col = Config.RARITY[f.def.rarity].color
			banner((if f.entry.size >= 4 then Config.SIZES[f.entry.size].name .. " " else "") .. f.def.name .. " hooked!", col)
			refreshHookIcons()
			if #hooked >= cast.hookCap then
				hintLabel.Text = "HOOK FULL  ·  REEL IT IN"
			end
		end
	end
end

-- names over the few fish nearest the hook (grey when your bait is too weak for them)
local function updateNameTags()
	local show = state == "swim" and cast ~= nil
	local near = {}
	if show then
		for _, f in fishes do
			if not f.isHooked and not f.ghost then
				local d = (f.p - hook).Magnitude
				if d < 130 then
					table.insert(near, { f = f, d = d })
				end
			end
		end
		table.sort(near, function(a, b)
			return a.d < b.d
		end)
	end
	local camera = workspace.CurrentCamera
	for i = 1, 5 do
		local tag = nameTags[i]
		if not tag and hud then
			tag = Ui.label(hud, { Text = "", Font = Ui.TECH, TextSize = 15, AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(240, 18), ZIndex = 19, TextXAlignment = Enum.TextXAlignment.Center })
			local st = Instance.new("UIStroke")
			st.Thickness = 1.5
			st.Color = Color3.fromRGB(10, 6, 30)
			st.Parent = tag
			nameTags[i] = tag
		end
		local n = near[i]
		if tag then
			if n then
				local f = n.f
				local sp, onScreen = camera:WorldToViewportPoint(worldOf(f.p - Vector2.new(0, f.w * 0.35)))
				tag.Visible = onScreen
				tag.Position = UDim2.fromOffset(sp.X, sp.Y)
				local gated = Config.RARITY[f.def.rarity].order > (cast.baitMax or 99)
				local far = f.entry.far
				tag.Text = if far then string.upper(f.def.name) .. "  ·  THROW FARTHER" elseif gated then string.upper(f.def.name) .. "  ·  NEEDS BETTER BAIT" else string.upper(f.def.name)
				tag.TextColor3 = if far or gated then Color3.fromRGB(150, 150, 170) else Config.RARITY[f.def.rarity].color
			else
				tag.Visible = false
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
				-- only the rarities you picked (and only what your bait can catch)
				local skip = not autoTargets[f.def.rarity] or order > (cast.baitMax or 99)
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
	if shakeAmp > 0.0005 then
		local a = shakeAmp * viewH * S
		camera.CFrame *= CFrame.new((math.random() - 0.5) * 2 * a, (math.random() - 0.5) * 2 * a, 0)
	end
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
	local slack = if state == "swim" or state == "fight" then 0 else 1.5
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
		seg.Color = if goldLine then Color3.fromRGB(255, 205, 90) else lineColor
		prev = p
	end
	hookPart.CFrame = CFrame.new(b)
	hookPart.Transparency = if out then 0 else 1
	local hb = hookPart:FindFirstChildOfClass("BillboardGui")
	if hb then
		hb.Enabled = false
	end
	if hookCard then
		-- the line ties on at the J's eye, near the top of the picture: hang the card just below the line's end
		hookCard.CFrame = planeCF(hook + Vector2.new(0, 2.4 / S * 0.3))
		local sg = hookCard:FindFirstChildOfClass("SurfaceGui")
		if sg then
			sg.Enabled = out
		end
	end
	-- fish on the hook dangle below it
	for i, f in hooked do
		f.p = hook + Vector2.new(0, 3 + i * f.w * 0.28)
		if f.model and f.model.Parent ~= f.g then
			f.model.Parent = f.g
		end
		placeFish(f, 90 * f.dir + math.sin(os.clock() * 6 + i) * 10)
	end
	depthPanel.Visible = state == "flight" or state == "swim" or state == "land" or state == "fight"
	if boostLabel then
		boostLabel.Visible = cast ~= nil and cast.boost == true
	end
end

---------------------------------------------------------------- the space shark
-- While you reel a fish up through the Reef or The Void a shark may come for it (Config.SHARK). Get the hook above
-- SHARK.escape before it reaches you, or it takes one fish off the hook. It hunts twice as often in the Abyss.

local function removeShark()
	if shark and shark.model then
		shark.model:Destroy()
	end
	shark = nil
end

local function updateShark(dt: number)
	local SH = Config.SHARK
	if not shark then
		if sharkRolled or #hooked == 0 or not SH.layers[Config.layerAt(math.max(0, hook.Y))] then
			return
		end
		sharkRolled = true
		local chance = SH.chance * (if hook.Y >= Config.ABYSS.from then 2 else 1)
		if math.random() >= chance then
			return
		end
		local src = FishModels and FishModels:FindFirstChild("rockjaw")
		if not src then
			return
		end
		local m = src:Clone()
		local w = 64
		m:ScaleTo(m:GetScale() * (w * S) / (m:GetAttribute("Length") or 2))
		for _, pt in m:GetDescendants() do
			if pt:IsA("BasePart") then
				pt.Color = pt.Color:Lerp(Color3.fromRGB(40, 44, 70), 0.75)
				pt.CastShadow = false
			end
		end
		m.Parent = folder
		local delay = SH.startDelay[1] + math.random() * (SH.startDelay[2] - SH.startDelay[1])
		shark = { model = m, w = w, dir = -1, p = hook + Vector2.new(170, 90), wait = delay, leaving = false, gone = 0 }
		placeFish(shark, 0)
		banner("A SPACE SHARK! REEL UP FAST!", Color3.fromRGB(255, 110, 110))
		kick(0.006)
		return
	end
	if shark.wait > 0 then
		shark.wait -= dt
		return
	end
	if not shark.leaving and (#hooked == 0 or hook.Y < SH.escape or state ~= "swim") then
		shark.leaving = true
		if #hooked > 0 then
			banner("You got away from the shark!", Ui.GREEN)
		end
	end
	local target = if shark.leaving then shark.p + Vector2.new(300, 120) else hook
	local d = target - shark.p
	if d.Magnitude > 0.1 then
		shark.p += d.Unit * math.min(d.Magnitude, SH.speed * (if shark.leaving then 1.5 else 1) * dt)
		shark.dir = if d.X >= 0 then 1 else -1
	end
	placeFish(shark, math.sin(os.clock() * 9) * 8)
	if shark.leaving then
		shark.gone += dt
		if shark.gone > 2.5 then
			removeShark()
		end
	elseif (hook - shark.p).Magnitude < 14 then
		-- got one
		local f = table.remove(hooked)
		if f then
			f.g:Destroy()
			local i = table.find(fishes, f)
			if i then
				table.remove(fishes, i)
			end
			banner("The shark stole your " .. f.def.name .. "!", Color3.fromRGB(255, 110, 110))
			sound(SFX.splash, 0.6, 0.7)
			kick(0.012, 0.06)
			refreshHookIcons()
		end
		shark.leaving = true
	end
end

-- what the next cast reaches (shown before you cast)
local function aimHint(): string
	if autoMode then
		return ""
	end
	if cast and cast.maxLen then
		local li = Config.layerAt(math.max(0, cast.maxLen + C.rodTip.Y - 1))
		return "TAP TO CAST  ·  REACHES " .. string.upper(Config.LAYERS[li].name)
	end
	return "TAP TO CAST"
end

local function finishCast()
	removeShark()
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
			table.clear(hooked)
			state = "aim"
			cast = nil
			hintLabel.Text = aimHint()
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
		local function arc(u)
			return flightFrom:Lerp(flightTo, u) - Vector2.new(0, math.sin(u * math.pi) * (40 + (flightTo.X - flightFrom.X) * 0.22))
		end
		hook = arc(tt)
		-- the camera follows the hook from the moment it leaves the rod, aiming a touch ahead of it so even a
		-- max-distance cast stays near the middle of the screen
		camTarget = arc(math.min(1, tt + 0.04))
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
		-- Straight drop: when you are not reeling the hook sinks steadily and drifts slowly back toward
		-- the dock; holding reels it straight up the line toward the rod. The line length holds it.
		local prevHook = hook
		local toRod = PIVOT - hook
		if holding then
			if toRod.Magnitude > 0.01 then
				hook += toRod.Unit * math.min(toRod.Magnitude, cast.reel * dt)
			end
		else
			hook += Vector2.new(-C.drift * dt, C.sinkSpeed * (cast.sink or 1) * dt) -- Hook Modification: sinks faster
			if hook.Y > 0 then
				hook = Vector2.new(math.max(C.minOut, hook.X), hook.Y)
			end
		end
		if cast.maxLen then
			local d = hook - PIVOT
			local m = d.Magnitude
			if m > cast.maxLen then
				-- past the line's length (a long cast, or sinking to the end of the line): it holds the hook
				if prevHook and (prevHook - PIVOT).Magnitude > cast.maxLen + 1 then
					hook = PIVOT + d.Unit * (m - (m - cast.maxLen) * math.min(1, dt * 3))
				else
					-- the line is fully out: the hook keeps sinking at full speed, swinging in on the line
					local u = d.Unit
					if not holding then
						local tan = Vector2.new(-u.Y, u.X) -- along the arc: down and toward the dock
						u = (u * cast.maxLen + tan * C.sinkSpeed * (cast.sink or 1) * dt).Unit
					end
					hook = PIVOT + u * cast.maxLen
				end
			end
		end
		lineLen = (hook - PIVOT).Magnitude
		local depth = math.max(0, hook.Y)
		maxDepthSeen = math.max(maxDepthSeen, depth)
		depthLabel.Text = ("%d M"):format(math.floor(depth))
		local li = Config.layerAt(depth)
		layerLabel.Text = if depth >= Config.ABYSS.from then ("THE ABYSS  +%d%%"):format(Config.ABYSS.bonusPct) else string.upper(Config.LAYERS[li].name)
		if li > lastLayer then
			lastLayer = li
			if li > 1 then
				banner(Config.LAYERS[li].name, Config.RARITY[Config.TOP_RARITY[li]].color)
			end
		end
		camTarget = Vector2.new(math.max(40, hook.X - 6), math.max(-24, hook.Y))
		updateFish(dt)
		checkCatch(prevHook)
		updateShark(dt)
		if lineLen <= C.minLine or (hook.Y < 0.5 and maxDepthSeen > 8) or now - (cast.t0 or now) > C.maxCastSeconds then
			finishCast()
		end
	elseif state == "fight" then
		updateFight(dt)
		updateFish(dt)
		camTarget = Vector2.new(math.max(40, hook.X - 6), math.max(-24, hook.Y))
	elseif state == "land" then
		updateFish(dt)
	else
		camTarget = AIM_CAM
		ambientFish(dt)
	end
	local wantH = if state == "swim" or state == "land" or state == "flight" or state == "fight" then SWIM_VIEW_H else AIM_VIEW_H
	-- during a cast the camera zooms out and tracks quickly; otherwise it eases gently
	local inFlight = state == "flight"
	viewH += (wantH - viewH) * (1 - math.exp(-dt * (if inFlight then 8 else 2.5)))
	cam = cam:Lerp(camTarget, 1 - math.exp(-dt * (if inFlight then 12 else 4)))
	drawScene()
	updateNameTags()
end

---------------------------------------------------------------- public

function View.init(callbacks)
	build()
	onFinish = callbacks.onFinish
	onState = callbacks.onState
	onLost = callbacks.onLost
	RunService.RenderStepped:Connect(function(dt)
		if state ~= "off" then
			local d = math.min(dt, 0.05)
			shakeAmp *= math.exp(-dt * 14)
			-- game time: almost frozen during a hit-stop, slower during slow motion
			if hitStop > 0 then
				hitStop -= dt
				d *= 0.05
			elseif slowMo > 0 then
				slowMo -= dt
				d *= 0.35
			end
			step(d)
			SeaDecor.update(d)
		else
			shakeAmp, hitStop, slowMo = 0, 0, 0
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
	if character then
		attachRod(character)
	end
	-- sea (0, 0) sits on the water just in front of the player
	local base = if hrp then hrp.Position + F * 2.4 else Vector3.zero
	origin = Vector3.new(base.X, WATER_Y, base.Z) - F * (PIVOT.X * S)
	savedWater = savedWater or workspace.Terrain.WaterColor
	-- (the view keeps the lobby's lighting: no exposure boost, so the sky and island look the same as on foot)
	closeHole()
	openHole()
	setSea("Fish")
	SeaDecor.build(folder, origin, F, R, S, CAM_SIDE) -- the scenery of every depth (see SeaDecor)
	if not seaFog then
		seaFog = Instance.new("ColorCorrectionEffect")
		seaFog.Name = "FishingSeaTint"
		seaFog.Enabled = false
		seaFog.Parent = game:GetService("Lighting")
	end
	-- (the sky behind the view is the lobby's own: the black hole stays hidden, as it is on the island)
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
	removeShark()
	if fight then
		fight = nil
		fightPanel.Visible = false
	end
	for _, tag in nameTags do
		tag.Visible = false
	end
	gui.Enabled = false
	closeHole()
	SeaDecor.clear()
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
		if hookCard and hookCard:FindFirstChildOfClass("SurfaceGui") then
			hookCard:FindFirstChildOfClass("SurfaceGui").Enabled = false
		end
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
		RodPose:FireServer("back")
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

-- which rarities Auto Fish goes after: { Common = true, ... }
function View.setAutoTargets(set)
	autoTargets = set
	autoTarget = nil
end

function View.setGoldLine(on: boolean)
	goldLine = on == true
end

function View.setLineColor(c: Color3)
	lineColor = c
end

-- Input: press/release from the main script (mouse, touch or key).
function View.press()
	if state == "aim" then
		state = "charge" -- a tap casts at full power (no power bar)
		chargeT = 0
		rodCue("windup")
	elseif state == "fight" then
		fightHold = true
	elseif state == "swim" and not autoMode then
		holding = true
		hook += (PIVOT - hook).Unit * C.tapReel * 0.35
	end
end

function View.release(): number?
	if state == "charge" then
		powerBar.Visible = false
		local p = 1
		state = "waiting"
		return p
	elseif state == "fight" then
		fightHold = false
	elseif state == "swim" and not autoMode then
		holding = false
		hook += (PIVOT - hook).Unit * C.tapReel * 0.65
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
	removeShark()
	sharkRolled = false
	lastLayer = 1
	maxDepthSeen = 0
	spooled = false
	holding = false
	autoTarget = nil
	power = p
	local dist = math.max(-PIVOT.Y + 8, cast.maxLen * p)
	_ = dist
	local reach = cast.reach or C.minReach or 0 -- Distance Throw decides where it lands (rarer fish live farther out)
	flightFrom = PIVOT
	flightTo = Vector2.new(PIVOT.X + reach, 0)
	t = 0
	state = "flight"
	rodCue("cast")
	sound(SFX.cast, 0.6)
	hintLabel.Text = ""
	refreshHookIcons()
	if onState then
		onState("flight")
	end
end

-- The next cast is ready (fetched while you aim). The sea's fish are always there: keep every
-- fish that is still in the server's pool, and add the new ones (replacing what was caught).
function View.prepare(serverCast)
	cast = serverCast
	if state == "aim" then
		hintLabel.Text = aimHint() -- (now it knows how deep this cast reaches)
	end
	local keep = {}
	for _, e in cast.pool or {} do
		keep[e.i] = e
	end
	for i = #fishes, 1, -1 do
		local f = fishes[i]
		local e = keep[f.entry.i]
		if f.isHooked then
			continue
		end
		if e and e.seed == f.entry.seed then
			f.entry = e
			keep[e.i] = nil -- already swimming
		else
			f.g:Destroy()
			table.remove(fishes, i)
		end
	end
	local first = #fishes == 0
	for _, e in keep do
		local L = Config.LAYERS[e.layer]
		local home = e.x or (((L and L.out) or 30) + 20 + (e.seed % 997) / 997 * C.seaWidth)
		local f = spawnFish(e, (e.seed % 2) == 0, home)
		if not e.moves then
			-- fish that don't patrol keep to their spot, swaying and bobbing (more lively the rarer they are)
			f.static = true
			f.amp *= 0.6
			f.dart *= 0.5
		end
		if not first then
			-- a newcomer replacing a caught fish: fade in, in case it's in view
			if f.model then
				f.fade = 0
				setFishAlpha(f, 0)
			else
				f.img.ImageTransparency = 1
				game:GetService("TweenService"):Create(f.img, TweenInfo.new(1.2), { ImageTransparency = 0 }):Play()
			end
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
		rodCue("windup")
		return 1
	end
	return nil
end

return View
