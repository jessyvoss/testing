-- Fish in Space: makes the pass displays' icons float and turn (runs on each player's client)
local RunService = game:GetService("RunService")
local folder = script.Parent
local icons = {}
for i, m in folder:GetChildren() do
	local icon = m:FindFirstChild("Icon")
	if icon then
		table.insert(icons, { model = icon, base = icon:GetPivot(), phase = i * 1.3, amp = m:GetAttribute("Bob") or 0.5 })
	end
end
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for _, it in icons do
		it.model:PivotTo(it.base * CFrame.new(0, math.sin(t * 1.6 + it.phase) * it.amp, 0) * CFrame.Angles(0, math.sin(t * 0.7 + it.phase) * 0.6, 0))
	end
end)
