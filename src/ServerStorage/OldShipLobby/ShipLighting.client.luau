-- Fish in Space: indoor / outdoor lighting. Inside the ship the light is clean and white; out on
-- the docks it goes back to the purple space night. Changes are local to this player.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
local atm = Lighting:FindFirstChildOfClass("Atmosphere")

-- the lobby and airlock volume
local INSIDE_MIN = Vector3.new(-82, 4, -64)
local INSIDE_MAX = Vector3.new(82, 48, 42)

local outdoor = {
	Lighting = { Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, ColorShift_Top = Lighting.ColorShift_Top, ExposureCompensation = Lighting.ExposureCompensation },
	CC = cc and { TintColor = cc.TintColor, Saturation = cc.Saturation } or nil,
	Atm = atm and { Density = atm.Density } or nil,
}
local indoor = {
	Lighting = { Ambient = Color3.fromRGB(150, 156, 172), OutdoorAmbient = Color3.fromRGB(170, 176, 192), ColorShift_Top = Color3.fromRGB(30, 34, 44), ExposureCompensation = outdoor.Lighting.ExposureCompensation + 0.25 },
	CC = cc and { TintColor = Color3.fromRGB(255, 255, 255), Saturation = 0.05 } or nil,
	Atm = atm and { Density = 0.05 } or nil,
}

local inside = nil
local info = TweenInfo.new(0.8, Enum.EasingStyle.Sine)
local function apply(preset)
	TweenService:Create(Lighting, info, preset.Lighting):Play()
	if cc and preset.CC then
		TweenService:Create(cc, info, preset.CC):Play()
	end
	if atm and preset.Atm then
		TweenService:Create(atm, info, preset.Atm):Play()
	end
end

RunService.Heartbeat:Connect(function()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local p = root.Position
	local now = p.X > INSIDE_MIN.X and p.X < INSIDE_MAX.X and p.Y > INSIDE_MIN.Y and p.Y < INSIDE_MAX.Y and p.Z > INSIDE_MIN.Z and p.Z < INSIDE_MAX.Z
	if now ~= inside then
		inside = now
		apply(if now then indoor else outdoor)
	end
end)
