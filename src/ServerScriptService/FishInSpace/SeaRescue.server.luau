-- Fish in Space: anyone who falls into the cosmic sea is lifted back onto the walkway.
local Players = game:GetService("Players")
local SAFE = CFrame.new(0, 31, 26) -- back onto the UFO deck, by the spawn
while true do
	for _, p in Players:GetPlayers() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and root.Position.Y < 20 then
			p.Character:PivotTo(SAFE)
		end
	end
	task.wait(0.5)
end
