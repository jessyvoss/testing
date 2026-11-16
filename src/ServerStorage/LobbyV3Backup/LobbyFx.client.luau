-- Fish in Space: slow drifting asteroids and flickering fire light around the lobby (client only).
local RunService = game:GetService("RunService")
local lobby = script.Parent
local rocks, lights = {}, {}
for _, r in lobby.FloatingAsteroids:GetChildren() do
	table.insert(rocks, { part = r, base = r.CFrame, spin = math.rad(r:GetAttribute("Drift") or 6), phase = math.random() * 6 })
end
for _, d in lobby.Fires:GetDescendants() do
	if d:IsA("PointLight") then
		table.insert(lights, { light = d, base = d.Brightness, phase = math.random() * 10 })
	end
end
local t = 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	for _, r in rocks do
		r.part.CFrame = r.base * CFrame.new(0, math.sin(t * 0.4 + r.phase) * 1.5, 0) * CFrame.Angles(t * r.spin * 0.3, t * r.spin * 0.5, 0)
	end
	for _, l in lights do
		l.light.Brightness = l.base * (0.8 + 0.25 * math.sin(t * 13 + l.phase) * math.sin(t * 7.3 + l.phase * 2))
	end
end)
