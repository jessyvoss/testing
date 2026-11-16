local Builder = {}
-- Procedural cherry blossom tree: gnarled trunk, wide branches, soft blossom clouds.
function Builder.cherry(origin: Vector3, seed: number, scale: number): Model
	local rng = Random.new(seed)
	local m = Instance.new("Model")
	m.Name = "CherryTree"
	local bark = Color3.fromRGB(52, 36, 46)
	local pinks = { Color3.fromRGB(255, 176, 206), Color3.fromRGB(255, 198, 222), Color3.fromRGB(242, 146, 190), Color3.fromRGB(255, 216, 234), Color3.fromRGB(232, 132, 182) }
	local function seg(a, b, r)
		local p = Instance.new("Part")
		p.Anchored = true
		p.Material = Enum.Material.Wood
		p.Color = bark
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new((b - a).Magnitude + r * 0.7, r * 2, r * 2)
		p.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
		p.Parent = m
	end
	local function blossom(c, rad, count)
		for _ = 1, count do
			local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.35, 0.8), rng:NextNumber(-1, 1))
			if dir.Magnitude < 0.01 then
				dir = Vector3.yAxis
			end
			local b = Instance.new("Part")
			b.Anchored = true
			b.CanCollide = false
			b.Shape = Enum.PartType.Ball
			b.Size = Vector3.one * rng:NextNumber(0.55, 1.05) * rad
			b.Material = Enum.Material.SmoothPlastic
			b.Color = pinks[rng:NextInteger(1, #pinks)]
			b.Position = c + dir.Unit * rng:NextNumber(0, 1) * rad
			b.Parent = m
		end
	end
	local function branch(a, dir, len, r, depth)
		local b = a + dir * len
		seg(a, b, r)
		if depth == 0 then
			blossom(b, 3.1 * scale, 14)
			return
		end
		local n = if depth == 3 then 4 else rng:NextInteger(2, 3)
		local base = rng:NextNumber(0, math.pi * 2)
		for i = 1, n do
			local yaw = base + (i / n) * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
			local tilt = rng:NextNumber(1.0, 1.32)
			local nd = (Vector3.yAxis * math.cos(tilt) + Vector3.new(math.cos(yaw), 0, math.sin(yaw)) * math.sin(tilt)).Unit
			nd = (nd + dir * 0.12 + Vector3.new(0, 0.12, 0)).Unit
			branch(b, nd, len * rng:NextNumber(0.68, 0.82), r * 0.64, depth - 1)
		end
		if depth == 1 then
			blossom(b, 3.3 * scale, 10)
		end
	end
	local p0 = origin
	local p1 = origin + Vector3.new(rng:NextNumber(-1.4, 1.4), 3.6 * scale, rng:NextNumber(-1.4, 1.4))
	seg(p0 - Vector3.new(0, 1, 0), p1, 1.35 * scale)
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2 + rng:NextNumber(-0.5, 0.5)
		seg(p0 + Vector3.new(0, 0.6, 0), p0 + Vector3.new(math.cos(a) * 2.2 * scale, -0.6, math.sin(a) * 2.2 * scale), 0.7 * scale)
	end
	local p2 = p1 + Vector3.new(rng:NextNumber(-2.2, 2.2), 2.6 * scale, rng:NextNumber(-2.2, 2.2))
	seg(p1, p2, 1.1 * scale)
	branch(p2, Vector3.yAxis, 7.5 * scale, 0.95 * scale, 3)
	return m
end
return Builder
