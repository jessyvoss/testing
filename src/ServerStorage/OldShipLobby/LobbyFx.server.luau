-- Fish in Space: lobby effects. Holo fish swim in circles around the atrium projector.
local RunService = game:GetService("RunService")
local lobby = workspace:WaitForChild("World"):WaitForChild("Lobby")
local orbit = lobby:WaitForChild("HoloFish")
local centre = Vector3.new(0, 8, 4)
local fish = {}
for _, p in orbit:GetChildren() do
	table.insert(fish, { part = p, i = p:GetAttribute("Orbit") or 0, y = p.Position.Y })
end
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for _, f in fish do
		local a = t * 0.45 + f.i * (math.pi * 2 / #fish)
		local r = 6.5 + math.sin(t * 0.7 + f.i) * 0.6
		local pos = centre + Vector3.new(math.cos(a) * r, f.y - centre.Y + math.sin(t * 1.3 + f.i) * 0.5, math.sin(a) * r)
		-- face along the direction of travel (the card's Z axis spans the fish's length)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		f.part.CFrame = CFrame.lookAt(pos, pos + tangent)
	end
end)
