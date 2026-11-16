-- Helpers for building the Fish in Space ship (the big hauler) out of parts.
local K = {}

K.WHITE = Color3.fromRGB(236, 239, 244)
K.PANEL = Color3.fromRGB(214, 219, 228)
K.GREY = Color3.fromRGB(150, 156, 168)
K.DARK = Color3.fromRGB(46, 50, 62)
K.CYAN = Color3.fromRGB(110, 225, 255)
K.RED = Color3.fromRGB(196, 62, 58)
K.PURPLE = Color3.fromRGB(160, 120, 255)
K.HULL = Color3.fromRGB(176, 182, 192)
K.HULL2 = Color3.fromRGB(152, 158, 170)
K.HULL3 = Color3.fromRGB(120, 126, 138)

-- Interior shape: floor y 8, ceiling y 44, walls at z = +-40, chamfered corners. Length x = +-80.
K.FLOOR = 8
K.CEIL = 44
K.HALF_X = 80
K.HALF_Z = 40
K.PROFILE = { { -34, 8 }, { 34, 8 }, { 40, 14 }, { 40, 36 }, { 32, 44 }, { -32, 44 }, { -40, 36 }, { -40, 14 } }

function K.part(parent, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color or K.WHITE
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props or {} do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

function K.wedge(parent, name, size, cf, color, material)
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color or K.HULL
	p.Material = material or Enum.Material.Metal
	p.Parent = parent
	return p
end

function K.cyl(parent, name, length, diameter, cf, color, material, props)
	-- cylinder whose axis is the CFrame's X axis
	local p = K.part(parent, name, Vector3.new(length, diameter, diameter), cf, color, material or Enum.Material.Metal, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

function K.neon(parent, name, size, cf, color)
	return K.part(parent, name, size, cf, color or K.CYAN, Enum.Material.Neon, { CastShadow = false })
end

-- A slab along a profile edge (points are {z, y}) spanning x0..x1.
function K.edge(parent, name, a, b, x0, x1, thick, offset, color, material, extend)
	local A = Vector3.new(0, a[2], a[1])
	local B = Vector3.new(0, b[2], b[1])
	local dir = (B - A).Unit
	local n = dir:Cross(Vector3.xAxis)
	local len = (B - A).Magnitude + (extend or 0)
	local mid = (A + B) / 2 + Vector3.new((x0 + x1) / 2, 0, 0) + n * offset
	local cf = CFrame.fromMatrix(mid, Vector3.xAxis, n)
	return K.part(parent, name, Vector3.new(math.abs(x1 - x0), thick, len), cf, color, material)
end

function K.halfWidth(y)
	if y <= 14 then
		return 34 + (y - 8)
	elseif y <= 36 then
		return 40
	end
	return 40 - (y - 36)
end

function K.light(part, face, range, brightness, color)
	local l = Instance.new("SurfaceLight")
	l.Face = face
	l.Range = range
	l.Brightness = brightness
	l.Angle = 120
	l.Color = color or Color3.fromRGB(225, 240, 255)
	l.Shadows = false
	l.Parent = part
	return l
end

function K.point(part, range, brightness, color)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = color or Color3.fromRGB(225, 240, 255)
	l.Shadows = false
	l.Parent = part
	return l
end

function K.gui(part, face, canvas, light)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.CanvasSize = canvas
	sg.LightInfluence = light or 0
	sg.Brightness = 1.4
	sg.Parent = part
	return sg
end

function K.text(parent, text, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = Enum.Font.Michroma
	l.TextColor3 = Color3.fromRGB(235, 245, 255)
	l.TextScaled = true
	l.Size = UDim2.fromScale(1, 1)
	for k, v in props or {} do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

-- Greebles: small machinery blocks scattered over a flat face.
-- cf = centre of the face, X/Y span the face, -Z points out of it (so blocks stick out along LookVector)
function K.greeble(parent, cf, w, h, count, rng, palette, maxDepth)
	palette = palette or { K.HULL, K.HULL2, K.HULL3, Color3.fromRGB(196, 200, 208) }
	for _ = 1, count do
		local sx = rng:NextNumber(0.6, 4.5)
		local sy = rng:NextNumber(0.6, 3.5)
		if rng:NextNumber() < 0.25 then sx *= 2.2 end
		local d = rng:NextNumber(0.25, maxDepth or 1.6)
		local x = rng:NextNumber(-w / 2 + sx / 2, w / 2 - sx / 2)
		local y = rng:NextNumber(-h / 2 + sy / 2, h / 2 - sy / 2)
		local c = palette[rng:NextInteger(1, #palette)]
		local r = rng:NextNumber()
		if r < 0.12 then
			K.cyl(parent, "Pipe", sx * 1.6, math.min(sy, 1.2), cf * CFrame.new(x, y, -d / 2), c)
		else
			K.part(parent, "Greeble", Vector3.new(sx, sy, d), cf * CFrame.new(x, y, -d / 2), c, Enum.Material.Metal)
		end
	end
end

-- A vent: dark recess with slats
function K.vent(parent, cf, w, h, slats)
	K.part(parent, "VentBack", Vector3.new(w, h, 0.3), cf * CFrame.new(0, 0, -0.15), K.DARK, Enum.Material.Metal)
	for i = 1, slats do
		local y = -h / 2 + (i - 0.5) * h / slats
		K.part(parent, "VentSlat", Vector3.new(w - 0.2, 0.18, 0.5), cf * CFrame.new(0, y, -0.35) * CFrame.Angles(math.rad(25), 0, 0), K.HULL2, Enum.Material.Metal)
	end
	K.part(parent, "VentFrame", Vector3.new(w + 0.6, 0.3, 0.6), cf * CFrame.new(0, h / 2 + 0.15, -0.3), K.HULL3, Enum.Material.Metal)
	K.part(parent, "VentFrame", Vector3.new(w + 0.6, 0.3, 0.6), cf * CFrame.new(0, -h / 2 - 0.15, -0.3), K.HULL3, Enum.Material.Metal)
end

-- A turbine face (for intakes and engine pods): ring, hub and fan blades, axis along cf's X
function K.turbine(parent, cf, radius, blades, color)
	K.cyl(parent, "TurbineBack", 0.4, radius * 2, cf * CFrame.new(-0.4, 0, 0), K.DARK)
	K.cyl(parent, "TurbineHub", 1.6, radius * 0.55, cf * CFrame.new(0.3, 0, 0), color or K.HULL)
	K.cyl(parent, "TurbineCone", 1, radius * 0.3, cf * CFrame.new(1.1, 0, 0), K.HULL3)
	for i = 0, blades - 1 do
		local a = i / blades * math.pi * 2
		K.part(parent, "Blade", Vector3.new(0.25, radius * 0.78, radius * 0.22), cf * CFrame.Angles(a, 0, 0) * CFrame.new(0, radius * 0.52, 0) * CFrame.Angles(0, math.rad(28), 0), K.HULL2, Enum.Material.Metal)
	end
end

return K
