-- Fish in Space: a living sky (client only).
--  * a purple galaxy band and soft nebula glows far away
--  * twinkling stars around the camera and slow glowing dust drifting round the island
--  * shooting stars every few seconds, and the odd bigger orange meteor
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Art = require(ReplicatedStorage:WaitForChild("FishInSpace"):WaitForChild("Art"))
local GLOW = Art.ui.glowdot

local folder = Instance.new("Folder")
folder.Name = "SkyFxLocal"
folder.Parent = workspace

local function anchor(name: string, size: Vector3, cf: CFrame): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cf
	p.Parent = folder
	return p
end

local function glowBillboard(pos: Vector3, size: number, color: Color3, transparency: number): (BasePart, ImageLabel)
	local p = anchor("Nebula", Vector3.new(1, 1, 1), CFrame.new(pos))
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(size, 0, size, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 100000
	bb.Parent = p
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = GLOW
	img.ImageColor3 = color
	img.ImageTransparency = transparency
	img.Parent = bb
	return p, img
end

---------------------------------------------------------------- galaxy band + nebula glows
local CENTER = Vector3.new(0, 30, 0)
local R = 2400
-- the band runs across the upper sky on a tilted great circle (like the reference: high on the right)
local bandFrame = CFrame.Angles(0, math.rad(35), 0) * CFrame.Angles(math.rad(48), 0, 0)
local bandColors = { Color3.fromRGB(150, 90, 255), Color3.fromRGB(90, 110, 255), Color3.fromRGB(210, 110, 255), Color3.fromRGB(110, 70, 220) }
local pulses = {}
local rng = Random.new(7)
for i = 0, 44 do
	local a = math.rad(-110 + i * 5)
	local dir = (bandFrame * CFrame.new(math.cos(a), 0, math.sin(a))).Position
	if dir.Y > -0.05 then
		local pos = CENTER + dir.Unit * R + Vector3.new(rng:NextNumber(-60, 60), rng:NextNumber(-60, 60), rng:NextNumber(-60, 60))
		local _, img = glowBillboard(pos, rng:NextNumber(650, 1100), bandColors[rng:NextInteger(1, #bandColors)], rng:NextNumber(0.4, 0.58))
		table.insert(pulses, { img = img, base = img.ImageTransparency, phase = rng:NextNumber(0, 6), speed = rng:NextNumber(0.15, 0.35) })
		-- a bright core blob now and then
		if i % 3 == 0 then
			local _, core = glowBillboard(pos, rng:NextNumber(220, 380), Color3.fromRGB(240, 220, 255), 0.4)
			table.insert(pulses, { img = core, base = 0.4, phase = rng:NextNumber(0, 6), speed = 0.5 })
		end
	end
end
-- a few separate coloured nebulae around the horizon
for i, info in { { -40, 18, Color3.fromRGB(80, 60, 200), 1300 }, { 120, 12, Color3.fromRGB(40, 120, 200), 1100 }, { 200, 25, Color3.fromRGB(170, 60, 160), 1200 }, { 300, 10, Color3.fromRGB(70, 40, 160), 1500 } } do
	local yaw, elev = math.rad(info[1]), math.rad(info[2])
	local dir = Vector3.new(math.cos(elev) * math.sin(yaw), math.sin(elev), math.cos(elev) * math.cos(yaw))
	local _, img = glowBillboard(CENTER + dir * (R + 300), info[4], info[3], 0.78)
	table.insert(pulses, { img = img, base = 0.78, phase = i, speed = 0.12 })
end

-- dense little stars along the band
for i = 0, 10 do
	local a = math.rad(-80 + i * 14)
	local dir = (bandFrame * CFrame.new(math.cos(a), 0, math.sin(a))).Position
	if dir.Y > 0 then
		local pos = CENTER + dir.Unit * (R - 200)
		local p = anchor("BandStars", Vector3.new(500, 500, 500), CFrame.lookAt(pos, CENTER))
		local e = Instance.new("ParticleEmitter")
		e.Texture = GLOW
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Rate = 40
		e.Lifetime = NumberRange.new(4, 8)
		e.Speed = NumberRange.new(0)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 13), NumberSequenceKeypoint.new(1, 0) })
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Color = ColorSequence.new(Color3.fromRGB(230, 220, 255), Color3.fromRGB(170, 150, 255))
		e.Parent = p
	end
end

---------------------------------------------------------------- twinkling stars around the camera
local starShell = anchor("StarShell", Vector3.new(1400, 1400, 1400), CFrame.new())
local twinkle = Instance.new("ParticleEmitter")
twinkle.Texture = GLOW
twinkle.Shape = Enum.ParticleEmitterShape.Sphere
twinkle.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
twinkle.Rate = 70
twinkle.Lifetime = NumberRange.new(3, 6)
twinkle.Speed = NumberRange.new(0)
twinkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 7), NumberSequenceKeypoint.new(1, 0) })
twinkle.LightEmission = 1
twinkle.LightInfluence = 0
twinkle.LockedToPart = true
twinkle.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(180, 210, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 240)) })
twinkle.Parent = starShell

---------------------------------------------------------------- glowing dust drifting round the island
local dustBox = anchor("SpaceDust", Vector3.new(320, 110, 320), CFrame.new(0, 50, 0))
local dust = Instance.new("ParticleEmitter")
dust.Texture = GLOW
dust.Shape = Enum.ParticleEmitterShape.Box
dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
dust.Rate = 30
dust.Lifetime = NumberRange.new(8, 14)
dust.Speed = NumberRange.new(0.6, 2.2)
dust.SpreadAngle = Vector2.new(180, 180)
dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.7), NumberSequenceKeypoint.new(1, 0) })
dust.Transparency = NumberSequence.new(0.2)
dust.LightEmission = 1
dust.LightInfluence = 0
dust.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 230, 255)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(190, 150, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 240)) })
dust.Parent = dustBox

---------------------------------------------------------------- shooting stars and meteors
local function shootingStar(big: boolean)
	local cam = workspace.CurrentCamera
	local c = cam.CFrame.Position
	-- start somewhere up in the sky in front-ish of the camera, streak down and across
	local yaw = math.rad(rng:NextNumber(-80, 80)) + math.atan2(-cam.CFrame.LookVector.X, -cam.CFrame.LookVector.Z)
	local elev = math.rad(rng:NextNumber(18, 55))
	local dist = rng:NextNumber(500, 900)
	local start = c + Vector3.new(-math.sin(yaw) * math.cos(elev), math.sin(elev), -math.cos(yaw) * math.cos(elev)) * dist
	local side = Vector3.new(math.cos(yaw), 0, -math.sin(yaw)) * (if rng:NextNumber() < 0.5 then -1 else 1)
	local dir = (side + Vector3.new(0, -rng:NextNumber(0.25, 0.6), 0)).Unit
	local len = if big then rng:NextNumber(300, 450) else rng:NextNumber(220, 380)
	local head = anchor("ShootingStar", Vector3.new(1, 1, 1), CFrame.lookAt(start, start + dir))
	head.Transparency = 0
	head.Shape = Enum.PartType.Ball
	head.Material = Enum.Material.Neon
	head.Color = if big then Color3.fromRGB(255, 190, 120) else Color3.fromRGB(230, 240, 255)
	head.Size = Vector3.new(1, 1, 1) * (if big then 5 else 3)
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, (if big then 5 else 2.6), 0); a0.Parent = head
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -(if big then 5 else 2.6), 0); a1.Parent = head
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Lifetime = if big then 0.7 else 0.45
	tr.LightEmission = 1
	tr.LightInfluence = 0
	tr.FaceCamera = true
	tr.WidthScale = NumberSequence.new(1, 0)
	tr.Transparency = NumberSequence.new(0, 1)
	tr.Color = if big then ColorSequence.new(Color3.fromRGB(255, 220, 160), Color3.fromRGB(255, 90, 30)) else ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 200, 255))
	tr.Parent = head
	local t = if big then rng:NextNumber(1.4, 1.9) else rng:NextNumber(0.8, 1.2)
	local tw = TweenService:Create(head, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(start + dir * len, start + dir * (len + 1)), Transparency = 1 })
	tw:Play()
	task.delay(t + tr.Lifetime + 0.1, function()
		head:Destroy()
	end)
end

task.spawn(function()
	while true do
		task.wait(rng:NextNumber(1.2, 3.5))
		shootingStar(rng:NextNumber() < 0.12)
		-- sometimes a little shower of two or three
		if rng:NextNumber() < 0.18 then
			for _ = 1, rng:NextInteger(1, 2) do
				task.wait(rng:NextNumber(0.15, 0.4))
				shootingStar(false)
			end
		end
	end
end)

---------------------------------------------------------------- the nebula sea far below the island (what you fish in)
local SEA_Y = -12
for i = 1, 22 do
	local a = rng:NextNumber(0, math.pi * 2)
	local r = rng:NextNumber(60, 520)
	local pos = Vector3.new(math.cos(a) * r, SEA_Y + rng:NextNumber(2, 9), math.sin(a) * r)
	local cols = { Color3.fromRGB(130, 80, 240), Color3.fromRGB(80, 70, 230), Color3.fromRGB(190, 80, 220), Color3.fromRGB(60, 120, 230) }
	local _, img = glowBillboard(pos, rng:NextNumber(240, 460), cols[rng:NextInteger(1, #cols)], rng:NextNumber(0.7, 0.84))
	table.insert(pulses, { img = img, base = img.ImageTransparency, phase = rng:NextNumber(0, 6), speed = rng:NextNumber(0.2, 0.45) })
end
-- stardust glittering on top of the nebula sea, all around the island
local seaGlitter = anchor("NebulaGlitter", Vector3.new(700, 2, 700), CFrame.new(0, SEA_Y + 2.5, 0))
local glit = Instance.new("ParticleEmitter")
glit.Texture = GLOW
glit.Shape = Enum.ParticleEmitterShape.Box
glit.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
glit.Rate = 120
glit.Lifetime = NumberRange.new(2, 4)
glit.Speed = NumberRange.new(0.5, 2)
glit.EmissionDirection = Enum.NormalId.Top
glit.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 1.4), NumberSequenceKeypoint.new(1, 0) })
glit.LightEmission = 1
glit.LightInfluence = 0
glit.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(170, 140, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 160, 240)) })
glit.Parent = seaGlitter
-- slow rolling violet mist over it
local seaMist = anchor("NebulaMist", Vector3.new(600, 4, 600), CFrame.new(0, SEA_Y + 1, 0))
local mist = Instance.new("ParticleEmitter")
mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
mist.Shape = Enum.ParticleEmitterShape.Box
mist.Rate = 14
mist.Lifetime = NumberRange.new(10, 16)
mist.Speed = NumberRange.new(0.3, 1)
mist.EmissionDirection = Enum.NormalId.Top
mist.SpreadAngle = Vector2.new(70, 70)
mist.Rotation = NumberRange.new(0, 360)
mist.RotSpeed = NumberRange.new(-5, 5)
mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 30), NumberSequenceKeypoint.new(1, 60) })
mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.82), NumberSequenceKeypoint.new(1, 1) })
mist.LightEmission = 0.7
mist.LightInfluence = 0
mist.Color = ColorSequence.new(Color3.fromRGB(150, 90, 255), Color3.fromRGB(80, 140, 255))
mist.Parent = seaMist

---------------------------------------------------------------- per frame: stars follow the camera, nebulae breathe
local t = 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	starShell.CFrame = CFrame.new(workspace.CurrentCamera.CFrame.Position)
	for _, p in pulses do
		p.img.ImageTransparency = math.clamp(p.base + math.sin(t * p.speed + p.phase) * 0.06, 0, 1)
	end
end)
