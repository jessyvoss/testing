-- Fish in Space: airlock doors. Each door slides open when someone walks up to it and closes
-- again behind them. The status light turns green while it is open.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local airlock = workspace:WaitForChild("World"):WaitForChild("Ship"):WaitForChild("Airlock")
local OPEN_DIST = 11
local INFO = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local RED = Color3.fromRGB(196, 62, 58)
local GREEN = Color3.fromRGB(80, 230, 130)

local doors = {}
for _, d in airlock:GetChildren() do
	if d:GetAttribute("Center") then
		local leaves = {}
		for _, n in { "LeafL", "LeafR" } do
			local leaf = d:FindFirstChild(n)
			if leaf then
				table.insert(leaves, { part = leaf, base = leaf.CFrame, closed = leaf:GetAttribute("ClosedX"), open = leaf:GetAttribute("OpenX") })
			end
		end
		table.insert(doors, { model = d, center = d:GetAttribute("Center"), leaves = leaves, isOpen = false, status = d:FindFirstChild("Status") })
	end
end

local function setDoor(door, open: boolean)
	if door.isOpen == open then
		return
	end
	door.isOpen = open
	for _, l in door.leaves do
		local dx = (if open then l.open else l.closed) - l.closed
		TweenService:Create(l.part, INFO, { CFrame = l.base + Vector3.new(dx, 0, 0) }):Play()
	end
	if door.status then
		door.status.Color = if open then GREEN else RED
		local light = door.status:FindFirstChildOfClass("PointLight")
		if light then
			light.Color = door.status.Color
		end
	end
end

while true do
	for _, door in doors do
		local near = false
		for _, p in Players:GetPlayers() do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - door.center).Magnitude < OPEN_DIST then
				near = true
				break
			end
		end
		setDoor(door, near)
	end
	task.wait(0.15)
end
