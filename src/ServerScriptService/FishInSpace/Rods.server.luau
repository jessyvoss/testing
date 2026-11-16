-- Fish in Space: every character carries their fishing rod on their back. While fishing it moves to the
-- right hand (the client poses both arms around it), and each cast bumps CastSeq so every client plays the swing.
-- God Fishing Rod pass owners carry the God Rod (with its aura) instead of the default rod.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("FishInSpace")
local Rods = Shared:WaitForChild("Rods")
local RodPose: RemoteEvent = Shared:WaitForChild("Remotes"):WaitForChild("RodPose")

-- rod frame: Grip at the hand point, rod along +Y, the tip bends toward +Z
local BACK = CFrame.new(-0.55, -0.85, 0.72) * CFrame.Angles(0, 0, math.rad(-35))        -- across the back, tip up over the right shoulder
local function handC0(hand: BasePart): CFrame
	-- matched to the two-handed hold pose (arm forward): rod forward and ~35 degrees up, tip drooping
	return CFrame.new(0, -hand.Size.Y * 0.4, 0) * CFrame.Angles(math.rad(-145), 0, 0) * CFrame.Angles(0, math.pi, 0)
end

local function rodWeld(char: Model): Weld?
	local rod = char:FindFirstChild("FishingRod")
	local grip = rod and rod:FindFirstChild("Grip")
	return grip and grip:FindFirstChild("RodWeld") :: Weld?
end

local function toBack(char: Model)
	local w = rodWeld(char)
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	if w and torso then
		w.Part0 = torso
		w.C0 = BACK
	end
end

local function toHand(char: Model)
	local w = rodWeld(char)
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if w and hand then
		w.Part0 = hand
		w.C0 = handC0(hand)
	end
end

local function giveRod(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local old = char:FindFirstChild("FishingRod")
	if old then
		old:Destroy()
	end
	local god = player:GetAttribute("Pass_GOD_ROD") == true
	local src = Rods:FindFirstChild(if god then "GodRod" else "DefaultRod")
	local torso = char:WaitForChild("UpperTorso", 5) or char:FindFirstChild("Torso")
	if not src or not torso then
		return
	end
	local rod = src:Clone()
	rod.Name = "FishingRod"
	for _, p in rod:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
		end
	end
	local grip = rod:FindFirstChild("Grip") :: BasePart
	local w = Instance.new("Weld")
	w.Name = "RodWeld"
	w.Part0 = torso
	w.Part1 = grip
	w.C0 = BACK
	w.Parent = grip
	rod.Parent = char
	if player:GetAttribute("RodState") == "hold" then
		toHand(char)
	end
end

RodPose.OnServerEvent:Connect(function(player: Player, state)
	local char = player.Character
	if not char then
		return
	end
	if state == "hold" then
		player:SetAttribute("RodState", "hold")
		toHand(char)
	elseif state == "back" then
		player:SetAttribute("RodState", nil)
		toBack(char)
	elseif state == "windup" and player:GetAttribute("RodState") == "hold" then
		player:SetAttribute("WindSeq", (player:GetAttribute("WindSeq") or 0) + 1)
	elseif state == "cast" and player:GetAttribute("RodState") == "hold" then
		player:SetAttribute("CastSeq", (player:GetAttribute("CastSeq") or 0) + 1)
	end
end)

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		player:SetAttribute("RodState", nil)
		task.wait(0.3)
		giveRod(player)
	end)
	player:GetAttributeChangedSignal("Pass_GOD_ROD"):Connect(function()
		giveRod(player)
	end)
	if player.Character then
		giveRod(player)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayer, p)
end
