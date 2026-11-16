-- Fish in Space: the pass stands' items float, bob and spin (runs on each player's client).
-- Stands can stream in after you join, so new ones are picked up as they arrive.
local RunService = game:GetService("RunService")
local folder = script.Parent
local SPIN = 1.6 -- radians per second (about one turn every 4 seconds)
local icons = {} -- [Model] = { base, phase, amp }
local count = 0

local function add(stand: Instance)
	local icon = stand:FindFirstChild("Icon")
	if icon and icon:IsA("Model") and not icons[icon] then
		count += 1
		icons[icon] = { base = icon:GetPivot(), phase = count * 1.3, amp = stand:GetAttribute("Bob") or 0.5 }
	end
end

for _, m in folder:GetChildren() do
	add(m)
end
folder.DescendantAdded:Connect(function(d)
	if d.Name == "Icon" and d.Parent and d.Parent.Parent == folder then
		task.defer(add, d.Parent)
	end
end)

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for icon, it in icons do
		if icon.Parent then
			icon:PivotTo(it.base * CFrame.new(0, math.sin(t * 1.6 + it.phase) * it.amp, 0) * CFrame.Angles(0, t * SPIN + it.phase, 0))
		else
			icons[icon] = nil
		end
	end
end)
