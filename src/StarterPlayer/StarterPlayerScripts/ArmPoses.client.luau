-- Fish in Space: arm poses that everyone sees, applied on every client for every character after animations
-- (works with both Motor6D and AnimationConstraint rigs):
--   * holding a fish ("HeldFish" in the character): both arms up, fish over the head
--   * fishing (player attribute RodState = "hold"): both hands on the rod, held out in front
--   * casting (CastSeq bumps for other players, LocalCastAt for you): wind up over the shoulder, then whip forward
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local me = Players.LocalPlayer
require(game:GetService("ReplicatedStorage"):WaitForChild("FishInSpace"):WaitForChild("FishAura")) -- preloads the aura textures

local PARTS = { RightShoulder = "RightUpperArm", LeftShoulder = "LeftUpperArm", RightElbow = "RightLowerArm", LeftElbow = "LeftLowerArm" }
local rad = math.rad

local OVERHEAD = {
	RightShoulder = CFrame.Angles(rad(165), 0, rad(-12)),
	LeftShoulder = CFrame.Angles(rad(165), 0, rad(12)),
	RightElbow = CFrame.Angles(rad(12), 0, 0),
	LeftElbow = CFrame.Angles(rad(12), 0, 0),
}

-- both-hands rod pose; the shoulder pitch (x) is animated for the cast
local function rodPose(rs: number, re: number, lsh: number, le: number)
	return {
		RightShoulder = CFrame.Angles(0, rad(12), 0) * CFrame.Angles(rad(rs), 0, 0),
		RightElbow = CFrame.Angles(rad(re), 0, 0),
		LeftShoulder = CFrame.Angles(0, rad(-28), 0) * CFrame.Angles(rad(lsh), 0, 0),
		LeftElbow = CFrame.Angles(rad(le), 0, 0),
	}
end
local HOLD = { 70, 20, 62, 35 }   -- right shoulder, right elbow, left shoulder, left elbow
local WIND = { 168, 48, 140, 62 } -- rod back over the shoulder
local FWD = { 38, 4, 38, 14 }     -- the whip: rod forward and down, line flying out
local WIND_TIME = 0.28   -- hold -> wound up (then it stays wound up until the cast launches)
local WHIP_TIME = 0.13   -- wound up -> forward, starts exactly when the line launches
local SETTLE_TIME = 0.4  -- forward -> back to the hold
local WIND_TIMEOUT = 4   -- a wind-up with no launch (cancelled cast) relaxes back to the hold

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function mix(p, q, k: number)
	return { p[1] + (q[1] - p[1]) * k, p[2] + (q[2] - p[2]) * k, p[3] + (q[3] - p[3]) * k, p[4] + (q[4] - p[4]) * k }
end

-- the arm angles for a player right now, from when they wound up and when their cast launched
local function castPose(now: number, wind: number?, cast: number?)
	if cast and now - cast < WHIP_TIME + SETTLE_TIME and (not wind or wind <= cast) then
		-- how far the wind-up got before the launch (a fast auto-cast may launch mid wind-up)
		local wound = if wind then smooth((cast - wind) / WIND_TIME) else 1
		local from = mix(HOLD, WIND, wound)
		local age = now - cast
		if age < WHIP_TIME then
			return mix(from, FWD, smooth(age / WHIP_TIME))
		end
		return mix(FWD, HOLD, smooth((age - WHIP_TIME) / SETTLE_TIME))
	end
	if wind and (not cast or wind > cast) and now - wind < WIND_TIMEOUT then
		return mix(HOLD, WIND, smooth((now - wind) / WIND_TIME))
	end
	return HOLD
end

local function apply(char: Model, pose)
	for joint, part in PARTS do
		local p = char:FindFirstChild(part)
		local j = p and p:FindFirstChild(joint)
		if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then
			j.Transform = pose[joint]
		end
	end
end

local castStart: { [Player]: number } = {}
local windStart: { [Player]: number } = {}
local function watch(plr: Player)
	-- other players: the server bumps WindSeq / CastSeq; you: your own client sets LocalWindAt / LocalCastAt instantly
	plr:GetAttributeChangedSignal("WindSeq"):Connect(function()
		if plr ~= me then
			windStart[plr] = os.clock()
		end
	end)
	plr:GetAttributeChangedSignal("CastSeq"):Connect(function()
		if plr ~= me then
			castStart[plr] = os.clock()
		end
	end)
	if plr == me then
		plr:GetAttributeChangedSignal("LocalWindAt"):Connect(function()
			windStart[plr] = os.clock()
		end)
		plr:GetAttributeChangedSignal("LocalCastAt"):Connect(function()
			castStart[plr] = os.clock()
		end)
	end
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(plr)
	castStart[plr] = nil
	windStart[plr] = nil
end)
for _, p in Players:GetPlayers() do
	watch(p)
end

RunService.Stepped:Connect(function()
	local now = os.clock()
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		if char then
			if char:FindFirstChild("HeldFish") then
				apply(char, OVERHEAD)
			elseif plr:GetAttribute("RodState") == "hold" then
				apply(char, rodPose(table.unpack(castPose(now, windStart[plr], castStart[plr]))))
			end
		end
	end
end)
