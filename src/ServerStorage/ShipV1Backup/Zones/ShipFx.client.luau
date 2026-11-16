-- Fish in Space: small client-side animations on the ship (holograms, star map, specimens).
local RunService = game:GetService("RunService")
local zones = script.Parent
local spins, models, bobs = {}, {}, {}
for _, d in zones:GetDescendants() do
	if d:IsA("BasePart") and d:GetAttribute("Spin") then
		table.insert(spins, { part = d, base = d.CFrame, rate = math.rad(d:GetAttribute("Spin")) })
	elseif d:IsA("Model") and d:GetAttribute("SpinModel") then
		local parts = {}
		local pivot = d:GetPivot()
		for _, p in d:GetDescendants() do
			if p:IsA("BasePart") then
				table.insert(parts, { part = p, rel = pivot:ToObjectSpace(p.CFrame) })
			end
		end
		table.insert(models, { pivot = pivot, parts = parts, rate = math.rad(d:GetAttribute("SpinModel")) })
	elseif d:IsA("BasePart") and d:GetAttribute("Bob") then
		table.insert(bobs, { part = d, base = d.CFrame, amp = d:GetAttribute("Bob"), phase = math.random() * 6 })
	end
end
local t = 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	for _, s in spins do
		s.part.CFrame = s.base * CFrame.Angles(0, t * s.rate, 0)
	end
	for _, m in models do
		local cf = m.pivot * CFrame.Angles(0, t * m.rate, 0)
		for _, p in m.parts do
			p.part.CFrame = cf * p.rel
		end
	end
	for _, b in bobs do
		b.part.CFrame = b.base * CFrame.new(0, math.sin(t * 1.3 + b.phase) * b.amp, 0) * CFrame.Angles(0, math.sin(t * 0.6 + b.phase) * 0.35, 0)
	end
end)
