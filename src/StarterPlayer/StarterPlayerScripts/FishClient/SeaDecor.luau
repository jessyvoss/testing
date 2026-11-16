-- Fish in Space: the scenery of the cosmic sea, a different look for every depth, placed in layers behind the fishing
-- plane (the camera has perspective, so things further back drift past slower: real parallax as you sink).
--   Stardust Shallows  light shafts slanting down from the surface, sparkling plankton
--   Nebula Drift       big soft nebula clouds and little star clusters, slowly drifting
--   Asteroid Reef      floating asteroid rocks studded with glowing crystals, slowly tumbling
--   The Void           near black: twinkling far stars, distant spiral galaxies, far-off purple lightning,
--                      and a black hole glowing at the very bottom
--   between areas      a faint glowing band where each new area starts
-- SeaDecor.build(parent, origin, F, R, S, side) makes it for one dock (the sea's axes); SeaDecor.update(dt) animates it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("FishInSpace")
local Config = require(Shared:WaitForChild("Config"))
local Art = require(Shared:WaitForChild("Art"))

local SeaDecor = {}

local TEX = {
	glow = "rbxassetid://87387475472568", -- soft radial glow
	ring = "rbxassetid://140643265343492", -- broken swirl ring
	bolt = "rbxassetid://84051551915337",
	wisp = "rbxassetid://104225267450271",
	dot = Art.ui.glowdot,
}
local SEA_X = { -80, 1150 } -- sea units the decor covers (left of the dock .. past the farthest cast)

local folder: Folder? = nil
local spinners = {} -- { model, base pivot, axis, speed }
local jellies = {} -- { model, base pivot, amp, freq, phase, sway }
local Models = Shared:WaitForChild("SeaModels", 10)
local drifters = {} -- { part, base CFrame, amp (studs along F), freq, phase }
local twinkles = {} -- { gui image, base transparency, freq, phase }
local t = 0

function SeaDecor.build(parent: Instance, origin: Vector3, F: Vector3, R: Vector3, S: number, side: number)
	if folder then
		folder:Destroy()
	end
	table.clear(spinners)
	table.clear(drifters)
	table.clear(twinkles)
	table.clear(jellies)
	folder = Instance.new("Folder")
	folder.Name = "SeaDecor"
	local rng = Random.new(77)
	local Y = Vector3.yAxis
	local toCam = R * side
	-- a point in the sea: x along the sea, y depth (sea units), back = studs behind the fishing plane
	local function at(x, y, back)
		return origin + F * (x * S) - Y * (y * S) - toCam * back
	end
	-- facing the camera (a card's Back face points at it)
	local function facing(pos: Vector3, rot: number?)
		return CFrame.fromMatrix(pos, F * side, Y) * CFrame.Angles(0, 0, rot or 0)
	end
	local function part(name, props)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in props do
			(p :: any)[k] = v
		end
		p.Parent = folder
		return p
	end
	-- a flat picture facing the camera
	local function card(tex, x, y, back, w, h, color, transp, rot, brightness)
		local p = part("Card", { Transparency = 1, Size = Vector3.new(w, h, 0.05), CFrame = facing(at(x, y, back), rot) })
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Back
		sg.LightInfluence = 0
		sg.Brightness = brightness or 1.4
		sg.CanvasSize = Vector2.new(256, 256)
		sg.Parent = p
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = tex
		img.ImageColor3 = color
		img.ImageTransparency = transp
		img.Parent = sg
		return p, img
	end
	local anchor = part("BeamAnchor", { Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(origin) })
	local function beam(a: Vector3, b: Vector3, w0, w1, color, transpTop, transpEnd, tex)
		local a0 = Instance.new("Attachment")
		a0.WorldPosition = a
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.WorldPosition = b
		a1.Parent = anchor
		local bm = Instance.new("Beam")
		bm.Attachment0 = a0
		bm.Attachment1 = a1
		bm.Width0 = w0
		bm.Width1 = w1
		bm.FaceCamera = true
		bm.Segments = 12
		bm.LightEmission = 1
		bm.LightInfluence = 0
		bm.Color = ColorSequence.new(color)
		bm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, transpTop), NumberSequenceKeypoint.new(0.25, transpTop), NumberSequenceKeypoint.new(1, transpEnd) })
		if tex then
			bm.Texture = tex
			bm.TextureMode = Enum.TextureMode.Stretch
		end
		bm.Parent = anchor
		return bm
	end
	local L = Config.LAYERS

	-- STARDUST SHALLOWS: light shafts slanting down from the surface
	for x = SEA_X[1], SEA_X[2], 95 do
		local xx = x + rng:NextNumber(-30, 30)
		local slant = rng:NextNumber(30, 70)
		local back = rng:NextNumber(14, 22)
		beam(at(xx, -2, back), at(xx + slant, rng:NextNumber(230, 330), back), rng:NextNumber(5, 8), rng:NextNumber(12, 18), Color3.fromRGB(190, 170, 255), rng:NextNumber(0.72, 0.82), 1)
	end
	-- a few soft glows hanging in the shallows
	for _ = 1, 14 do
		local _, img = card(TEX.glow, rng:NextNumber(SEA_X[1], SEA_X[2]), rng:NextNumber(40, 330), rng:NextNumber(16, 24), 26, 26, Color3.fromRGB(150, 120, 255), 0.8)
		table.insert(twinkles, { img = img, base = 0.8, amp = 0.06, freq = rng:NextNumber(0.2, 0.5), phase = rng:NextNumber(0, 6) })
	end

	-- NEBULA DRIFT: big soft clouds and star clusters, drifting slowly
	local NEB = { Color3.fromRGB(255, 90, 200), Color3.fromRGB(160, 90, 255), Color3.fromRGB(70, 210, 230), Color3.fromRGB(90, 130, 255), Color3.fromRGB(255, 130, 120) }
	for _ = 1, 34 do
		local size = rng:NextNumber(26, 70)
		local p = card(TEX.glow, rng:NextNumber(SEA_X[1], SEA_X[2]), rng:NextNumber(L[2].from - 40, L[2].to + 30), rng:NextNumber(10, 24), size * rng:NextNumber(1.2, 1.8), size, NEB[rng:NextInteger(1, #NEB)], rng:NextNumber(0.5, 0.7), rng:NextNumber(-0.4, 0.4), 1.6)
		table.insert(drifters, { part = p, base = p.CFrame, dir = F, amp = rng:NextNumber(1.5, 4), freq = rng:NextNumber(0.03, 0.08), phase = rng:NextNumber(0, 6) })
	end
	for _ = 1, 16 do -- star clusters
		local cx, cy = rng:NextNumber(SEA_X[1], SEA_X[2]), rng:NextNumber(L[2].from, L[2].to)
		local back = rng:NextNumber(12, 22)
		for _ = 1, rng:NextInteger(5, 9) do
			local _, img = card(TEX.dot, cx + rng:NextNumber(-14, 14), cy + rng:NextNumber(-10, 10), back, 1.4, 1.4, Color3.fromRGB(255, 240, 255), 0.1)
			table.insert(twinkles, { img = img, base = 0.15, amp = 0.35, freq = rng:NextNumber(0.6, 1.6), phase = rng:NextNumber(0, 6) })
		end
	end

	-- the Blender models (ReplicatedStorage.FishInSpace.SeaModels): a copy, scaled and placed, facing a random way
	local function model(name: string, x, y, back, scale, rot: CFrame?)
		local src = Models and Models:FindFirstChild(name)
		if not src then
			return nil
		end
		local m = src:Clone()
		m:ScaleTo(m:GetScale() * scale)
		m:PivotTo(CFrame.new(at(x, y, back)) * (rot or CFrame.new()))
		m.Parent = folder
		return m
	end
	local function randomTurn()
		return CFrame.Angles(rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3))
	end

	-- ASTEROID REEF: crystal asteroids and crystal clusters, slowly tumbling
	local ROCKS = { "AsteroidA", "AsteroidB", "AsteroidC", "AsteroidD", "AsteroidE", "AsteroidF" }
	for _ = 1, 40 do
		local m = model(ROCKS[rng:NextInteger(1, #ROCKS)], rng:NextNumber(SEA_X[1], SEA_X[2]), rng:NextNumber(L[3].from - 20, L[3].to + 40), rng:NextNumber(6, 24), rng:NextNumber(0.35, 1.1), randomTurn())
		if m then
			table.insert(spinners, { model = m, base = m:GetPivot(), axis = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit, speed = rng:NextNumber(0.03, 0.12) * (if rng:NextNumber() < 0.5 then -1 else 1) })
			-- some crystals light up the rocks around them
			if rng:NextNumber() < 0.35 then
				local glow = m:FindFirstChildWhichIsA("BasePart")
				for _, p in m:GetChildren() do
					if p:IsA("BasePart") and p.Material == Enum.Material.Neon then
						glow = p
					end
				end
				local light = Instance.new("PointLight")
				light.Color = glow.Color
				light.Range = 14
				light.Brightness = 1.2
				light.Shadows = false
				light.Parent = glow
			end
		end
	end
	local CLUSTERS = { "CrystalClusterA", "CrystalClusterB", "CrystalClusterC" }
	for _ = 1, 18 do
		local y = if rng:NextNumber() < 0.7 then rng:NextNumber(L[3].from, L[3].to) else rng:NextNumber(L[2].from + 60, L[2].to)
		local m = model(CLUSTERS[rng:NextInteger(1, #CLUSTERS)], rng:NextNumber(SEA_X[1], SEA_X[2]), y, rng:NextNumber(5, 20), rng:NextNumber(0.8, 1.8), randomTurn())
		if m then
			table.insert(spinners, { model = m, base = m:GetPivot(), axis = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit, speed = rng:NextNumber(0.05, 0.15) })
		end
	end

	-- SPACE JELLYFISH: drifting and bobbing through the Shallows and Nebula Drift
	for _ = 1, 22 do
		local y = rng:NextNumber(60, L[2].to - 40)
		local m = model(if rng:NextNumber() < 0.5 then "JellyA" else "JellyB", rng:NextNumber(SEA_X[1], SEA_X[2]), y, rng:NextNumber(6, 22), rng:NextNumber(0.4, 0.9), CFrame.Angles(0, rng:NextNumber(0, 6.3), rng:NextNumber(-0.25, 0.25)))
		if m then
			table.insert(jellies, { model = m, base = m:GetPivot(), amp = rng:NextNumber(0.8, 2), freq = rng:NextNumber(0.12, 0.25), phase = rng:NextNumber(0, 6), sway = rng:NextNumber(0.5, 1.5) })
		end
	end

	-- a reddish glow deep in the reef
	for _ = 1, 10 do
		card(TEX.glow, rng:NextNumber(SEA_X[1], SEA_X[2]), rng:NextNumber(L[3].from, L[3].to), rng:NextNumber(20, 25), 60, 40, Color3.fromRGB(200, 60, 160), 0.78)
	end

	-- THE VOID: far stars, distant galaxies, lightning, and the black hole at the bottom
	for _ = 1, 110 do
		local _, img = card(TEX.dot, rng:NextNumber(SEA_X[1], SEA_X[2]), rng:NextNumber(L[4].from - 60, L[4].to), rng:NextNumber(18, 25), rng:NextNumber(0.5, 1.3), 1, Color3.fromRGB(230, 220, 255), 0.2)
		img.Parent.Parent.Size = Vector3.new(img.Parent.Parent.Size.X, img.Parent.Parent.Size.X, 0.05)
		table.insert(twinkles, { img = img, base = 0.25, amp = 0.5, freq = rng:NextNumber(0.3, 1.4), phase = rng:NextNumber(0, 6) })
	end
	local GAL = { Color3.fromRGB(150, 110, 255), Color3.fromRGB(90, 160, 255), Color3.fromRGB(255, 120, 200) }
	for _ = 1, 16 do
		local x, y, back = rng:NextNumber(SEA_X[1], 700), rng:NextNumber(L[4].from + 40, 2150), rng:NextNumber(20, 25)
		local size = rng:NextNumber(16, 34)
		local col = GAL[rng:NextInteger(1, #GAL)]
		local rot = rng:NextNumber(0, 6.3)
		card(TEX.glow, x, y, back, size * 1.2, size * 0.5, col, 0.45, rot, 1.8)
		local p = card(TEX.ring, x, y, back - 0.2, size, size * 0.45, col, 0.3, rot, 1.8)
		table.insert(drifters, { part = p, base = p.CFrame, spin = rng:NextNumber(0.03, 0.08) })
		card(TEX.dot, x, y, back - 0.4, size * 0.18, size * 0.18, Color3.fromRGB(255, 245, 220), 0.05, 0, 2)
	end
	-- far-off lightning in the void
	local boltBox = part("VoidLightning", {
		Transparency = 1,
		Size = Vector3.new((SEA_X[2] - SEA_X[1]) * S, (L[4].to - L[4].from) * S * 0.8, 1),
		CFrame = facing(at((SEA_X[1] + SEA_X[2]) / 2, (L[4].from + L[4].to) / 2, 24)),
	})
	local bolts = Instance.new("ParticleEmitter")
	bolts.Texture = TEX.bolt
	bolts.Shape = Enum.ParticleEmitterShape.Box
	bolts.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	bolts.Rate = 1.2
	bolts.Lifetime = NumberRange.new(0.08, 0.18)
	bolts.Speed = NumberRange.new(0, 0)
	bolts.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 11) })
	bolts.Rotation = NumberRange.new(0, 360)
	bolts.Color = ColorSequence.new(Color3.fromRGB(200, 120, 255), Color3.fromRGB(255, 150, 240))
	bolts.LightEmission = 1
	bolts.LightInfluence = 0
	bolts.Transparency = NumberSequence.new(0.2)
	bolts.Parent = boltBox
	-- the black hole: a dark heart in a bright, spinning accretion ring at the very bottom
	do
		local maxDepth = Config.UPGRADES.tether.values[#Config.UPGRADES.tether.values] + Config.CAST.rodTip.Y
		local bx, by = 260, maxDepth + 150 -- its glow and disk rise into view from the bottom at your deepest
		card(TEX.glow, bx, by, 25, 150, 90, Color3.fromRGB(255, 110, 200), 0.3, 0, 2)
		local hole = model("BlackHole", bx, by, 23, 1.8, CFrame.Angles(0, 0, 0))
		if hole then
			-- the disk spins around its own axis (the model is built flat, tipped slightly toward you)
			table.insert(spinners, { model = hole, base = hole:GetPivot(), axis = hole:GetPivot().UpVector, speed = 0.15 })
		end
	end

	-- the start of each new area: a faint glowing band across the sea
	for li = 2, #L do
		local col = Config.RARITY[Config.TOP_RARITY[li]].color
		beam(at(SEA_X[1], L[li].from, 20), at(SEA_X[2], L[li].from, 20), 5, 5, col, 0.86, 0.86, TEX.wisp)
	end

	folder.Parent = parent
	return folder
end

function SeaDecor.update(dt: number)
	if not folder or not folder.Parent then
		return
	end
	t += dt
	for _, sp in spinners do
		sp.model:PivotTo(CFrame.new(sp.base.Position) * CFrame.fromAxisAngle(sp.axis, t * sp.speed) * sp.base.Rotation)
	end
	for _, j in jellies do
		-- a slow pulse-and-glide: up and down, swaying a little
		local bob = math.sin(t * j.freq * 6.283 + j.phase)
		j.model:PivotTo(j.base + Vector3.yAxis * bob * j.amp)
		_ = j.sway
	end
	for _, d in drifters do
		if d.spin then
			d.part.CFrame = d.base * CFrame.Angles(0, 0, t * d.spin)
		else
			d.part.CFrame = d.base + d.dir * math.sin(t * d.freq * 6.283 + d.phase) * d.amp
		end
	end
	for _, w in twinkles do
		w.img.ImageTransparency = math.clamp(w.base + math.sin(t * w.freq * 6.283 + w.phase) * w.amp, 0, 1)
	end
end

function SeaDecor.clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(spinners)
	table.clear(drifters)
	table.clear(twinkles)
	table.clear(jellies)
end

return SeaDecor
