-- Fish in Space: trailer helpers for recording the gameplay video. STUDIO ONLY: this does nothing in a live game.
--   F6  fly-in: the camera swoops in high over the island and settles behind your character (about 5 seconds)
--   H   clean shot: hides every menu, HUD and Roblox's own top bar (the fishing view and fights stay); press again to bring them back
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer

local flying = false
local function flyIn()
	if flying then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	flying = true
	local cam = workspace.CurrentCamera
	local island = Vector3.new(0, 30, 0)
	local finish = root.CFrame * CFrame.new(2, 4, 13)
	local keys = {
		{ CFrame.lookAt(Vector3.new(-230, 170, -300), island), 0 },             -- high and far, the whole island in view
		{ CFrame.lookAt(Vector3.new(-40, 95, -190), island + Vector3.new(30, 0, 0)), 1.8 },
		{ CFrame.lookAt(finish.Position + Vector3.new(-25, 30, -35), root.Position), 1.7 },
		{ CFrame.lookAt(finish.Position, root.Position + Vector3.new(0, 2, 0)), 1.5 },
	}
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = keys[1][1]
	task.wait(0.4)
	for i = 2, #keys do
		local tw = TweenService:Create(cam, TweenInfo.new(keys[i][2], if i == #keys then Enum.EasingStyle.Quad else Enum.EasingStyle.Sine, if i == 2 then Enum.EasingDirection.In elseif i == #keys then Enum.EasingDirection.Out else Enum.EasingDirection.InOut), { CFrame = keys[i][1] })
		tw:Play()
		tw.Completed:Wait()
	end
	cam.CameraType = Enum.CameraType.Custom
	flying = false
end

local hidden = false
local KEEP = { FishingView = true }
local wasEnabled = {}
local function setClean(on)
	hidden = on
	for _, g in player.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and not KEEP[g.Name] then
			if on then
				wasEnabled[g] = g.Enabled
				g.Enabled = false
			elseif wasEnabled[g] ~= nil then
				g.Enabled = wasEnabled[g]
			end
		end
	end
	if not on then
		table.clear(wasEnabled)
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, not on)
	end)
	pcall(function()
		StarterGui:SetCore("TopbarEnabled", not on)
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F6 then
		task.spawn(flyIn)
	elseif input.KeyCode == Enum.KeyCode.H then
		setClean(not hidden)
	end
end)
print("[Trailer] Studio helpers ready: F6 fly-in, H hide/show UI")
