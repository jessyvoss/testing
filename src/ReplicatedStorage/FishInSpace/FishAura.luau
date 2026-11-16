-- Fish in Space: Dragon-Ball-style rarity auras. The heart of it is a hollow, feathery flame shell that hugs the
-- fish and flickers (a 4-frame flipbook drawn for this game, shown as overlapping short-lived sprites), with a soft
-- inner glow, fine streaks of energy rising off it, a bright outline on the rarer fish and crackling lightning.
-- Used for fish you've pulled out (held over your head) and the God Rod. Fish in the sea have no aura. Textures: LobbyAssets/Aura/*.py
-- FishAura.apply(model, rarity, opts?) -> aura part (nil for Junk)
--   opts.highlight = false  skip the Highlight outline (clients render only a limited number of Highlights)
local FishAura = {}

FishAura.TEX = {
	shell = "rbxassetid://95069631832373", -- 2x2 flipbook
	glow = "rbxassetid://87387475472568",
	streak = "rbxassetid://125766005968824",
	bolt = "rbxassetid://84051551915337",
}

-- per rarity: aura colour, shell opacity (0 = solid) and size (x fish length), flicker rate, extras
FishAura.TIERS = {
	Common = { color = Color3.fromRGB(70, 230, 205), shell = 0.5, scale = 1.0, rate = 8, streaks = 2, bolts = 0, light = 0.6, outline = nil },
	Uncommon = { color = Color3.fromRGB(80, 170, 255), shell = 0.32, scale = 1.04, rate = 12, streaks = 5, bolts = 0, light = 1.0, outline = nil },
	Rare = { color = Color3.fromRGB(220, 85, 255), shell = 0.28, scale = 1.08, rate = 16, streaks = 10, bolts = 2, light = 1.6, outline = 0.92 },
	Epic = { color = Color3.fromRGB(255, 215, 60), shell = 0.15, scale = 1.12, rate = 22, streaks = 18, bolts = 5, light = 2.4, outline = 0.88,
		outer = Color3.fromRGB(255, 60, 40), boltColor = Color3.fromRGB(255, 120, 80) },
}

-- how much bigger each rarity is when you hold it up (3.2 studs x catch size x this)
FishAura.HOLD_SCALE = { Junk = 1, Common = 1, Uncommon = 1.5, Rare = 6.9, Epic = 15 }

-- An energy skin that hugs the object's exact shape: a slightly bigger copy of every visible piece in
-- ForceField material (it shimmers and glows on its own), welded on. layers = { {pad = studs, color, t = transparency} }.
-- Thin pieces (fishing line) are skipped. Returns the folder of shells (named "AuraShells").
function FishAura.wrap(model: Instance, layers: { any }): Folder
	local old = model:FindFirstChild("AuraShells")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "AuraShells"
	local pieces = {}
	for _, p in model:GetDescendants() do
		if p:IsA("MeshPart") and p.Transparency < 0.9 and not p:FindFirstAncestor("AuraShells") and math.min(p.Size.X, p.Size.Y, p.Size.Z) > 0.06 then
			table.insert(pieces, p)
		end
	end
	for _, p in pieces do
		for i, L in layers do
			local sh = p:Clone()
			sh:ClearAllChildren()
			sh.Name = "Shell" .. i
			sh.Size = p.Size + Vector3.one * (L.pad * 2)
			sh.CFrame = p.CFrame
			sh.Material = Enum.Material.ForceField
			sh.Color = L.color
			sh.Transparency = L.t or 0
			sh.CastShadow = false
			sh.CanCollide = false
			sh.CanQuery = false
			sh.CanTouch = false
			sh.Massless = true
			sh.Anchored = p.Anchored
			if not p.Anchored then
				local w = Instance.new("Weld") -- (a Weld, not a WeldConstraint: this survives being cloned)
				w.Part0 = p
				w.Part1 = sh
				w.C0 = CFrame.new()
				w.Parent = sh
			end
			sh.Parent = folder
		end
	end
	folder.Parent = model
	return folder
end

local function seq(...)
	local a = { ... }
	local k = {}
	for i = 1, #a, 2 do
		table.insert(k, NumberSequenceKeypoint.new(a[i], a[i + 1]))
	end
	return NumberSequence.new(k)
end

local function emitter(parent: Instance, name: string, tex: string)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = tex
	e.LightInfluence = 0
	e.Speed = NumberRange.new(0, 0)
	e.Parent = parent
	return e
end

-- the flickering shell, centred on an attachment, locked to the fish so it moves with it
local function shell(att: Attachment, color: Color3, size: number, squash: number, opacity: number, rate: number, z: number)
	local e = emitter(att, "AuraShell", FishAura.TEX.shell)
	e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
	e.FlipbookMode = Enum.ParticleFlipbookMode.Random
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.45
	e.Brightness = 1.6
	e.Size = seq(0, size * 0.96, 1, size * 1.04)
	e.Squash = NumberSequence.new(squash)
	e.Transparency = seq(0, 1, 0.15, opacity, 0.7, opacity, 1, 1)
	e.Lifetime = NumberRange.new(0.4, 0.65)
	e.Rate = rate
	e.LockedToPart = true
	e.ZOffset = z
	return e
end

function FishAura.apply(model: Model, rarity: string, opts: { highlight: boolean? }?)
	local tier = FishAura.TIERS[rarity]
	if not tier then
		return nil
	end
	local cf, size = model:GetBoundingBox()
	local L = math.max(size.X, size.Z) -- fish length
	local p = Instance.new("Part")
	p.Name = "Aura"
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Size = Vector3.new(size.X, size.Y * 0.8, size.Z)
	p.CFrame = cf
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if anchor and anchor.Anchored then
		p.Anchored = true
	elseif anchor then
		local w = Instance.new("WeldConstraint")
		w.Part0 = anchor
		w.Part1 = p
		w.Parent = p
	end
	-- the aura hugs the body: sized from the fish's thickness, with several shells running along a long fish
	local long = size.X >= size.Z and Vector3.xAxis or Vector3.zAxis
	local T = math.clamp(math.min(size.Y, math.min(size.X, size.Z)), L * 0.18, L * 0.6) -- body thickness
	local S = T * 1.75 * tier.scale -- a rim of flame shows all round the body
	local n = math.clamp(math.ceil(L / (S * 0.8)), 1, 7)
	local step = n > 1 and (L - S * 0.9) / (n - 1) or 0
	local att
	for i = 1, n do
		local at = Instance.new("Attachment")
		at.Name = "AuraCenter"
		at.Position = long * ((i - 1) * step - (n - 1) * step / 2) + Vector3.new(0, T * 0.06, 0)
		at.Parent = p
		att = att or at
		local r = math.max(7, tier.rate * 0.9) -- per shell (enough that several are always alive)
		if tier.outer then
			shell(at, tier.outer, S * 1.12, -0.45, math.min(0.6, tier.shell + 0.25), r * 0.7, -T * 0.45)
		end
		shell(at, tier.color, S, -0.45, tier.shell, r, -T * 0.35)
		-- soft light right around the body (the white-hot inner edge of the aura)
		local g = emitter(at, "AuraGlow", FishAura.TEX.glow)
		g.Color = ColorSequence.new(tier.color:Lerp(Color3.new(1, 1, 1), 0.55))
		g.LightEmission = 1
		g.Size = NumberSequence.new(S * 0.8)
		g.Squash = NumberSequence.new(-0.5)
		g.Transparency = seq(0, 1, 0.3, 0.55 + tier.shell * 0.4, 0.7, 0.55 + tier.shell * 0.4, 1, 1)
		g.Lifetime = NumberRange.new(0.5, 0.7)
		g.Rate = 4
		g.LockedToPart = true
		g.ZOffset = -T * 0.25
	end
	-- 3) fine streaks of energy rising off the aura
	if tier.streaks > 0 then
		local st = emitter(p, "AuraStreaks", FishAura.TEX.streak)
		st.Color = ColorSequence.new(Color3.new(1, 1, 1), tier.color)
		st.LightEmission = 1
		st.Size = seq(0, T * 0.12, 1, T * 0.05)
		st.Squash = NumberSequence.new(1.6) -- tall and thin
		st.Transparency = seq(0, 0.15, 1, 1)
		st.Lifetime = NumberRange.new(0.2, 0.35)
		st.Rate = tier.streaks
		st.Speed = NumberRange.new(T * 0.6, T * 1.0)
		st.EmissionDirection = Enum.NormalId.Top
		st.SpreadAngle = Vector2.new(5, 5)
		st.Shape = Enum.ParticleEmitterShape.Box
		st.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	end
	-- 4) crackling lightning on the rarest fish
	if tier.bolts > 0 then
		local b = emitter(att, "AuraLightning", FishAura.TEX.bolt)
		b.Color = ColorSequence.new(tier.boltColor or Color3.new(1, 1, 1), Color3.new(1, 1, 1))
		b.LightEmission = 1
		b.Size = seq(0, T * 0.35, 1, T * 0.45)
		b.Transparency = seq(0, 0, 0.7, 0.2, 1, 1)
		b.Lifetime = NumberRange.new(0.07, 0.14)
		b.Rate = tier.bolts
		b.Rotation = NumberRange.new(0, 360)
		b.Shape = Enum.ParticleEmitterShape.Sphere
		b.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		b.LockedToPart = true
	end
	-- glow light
	local light = Instance.new("PointLight")
	light.Color = tier.color:Lerp(Color3.new(1, 1, 1), 0.65) -- near-white, so it lights the fish without dyeing it
	light.Brightness = tier.light * 0.6
	light.Range = math.clamp(T * 1.5, 6, 16)
	light.Shadows = false
	light.Parent = p
	-- bright outline (the light edge right against the body in the references)
	if tier.outline and not (opts and opts.highlight == false) then
		local h = Instance.new("Highlight")
		h.Name = "AuraOutline"
		h.Adornee = model
		h.FillColor = tier.color
		h.FillTransparency = 1 -- outline only: the fish keeps its own colours
		h.OutlineColor = tier.color:Lerp(Color3.new(1, 1, 1), 0.7)
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = model
	end
	p.Parent = model
	-- the energy skin that wraps the fish's own shape (sized to the fish's thickness)
	FishAura.wrap(model, {
		-- one faint layer a little way out from the body: a shimmer round the edge that you see the fish through
		{ pad = T * 0.06, color = tier.outer or tier.color, t = 0.82 },
	})
	return p
end

-- download the aura textures up front on each client (a brand-new texture otherwise shows nothing for a few seconds)
if game:GetService("RunService"):IsClient() then
	task.spawn(function()
		local ids = {}
		for _, id in FishAura.TEX do
			table.insert(ids, id)
		end
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(ids)
		end)
	end)
end
return FishAura
