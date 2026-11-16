-- Fish in Space: brings Zorp to life (runs on each player's own screen). Each Zorp is made of separate pieces
-- (ZorpBody, ZorpHead, ZorpEyes, ZorpAntennaL/R, ZorpArmL/R, ZorpRod, ZorpBucket); every frame they're posed
-- around their joints (the "Joint" attribute, in Zorp's own units from the feet):
--   breathing and a lazy sway, head turns to look at you, blinks, wobbly antennae, the rod bobs, he lifts his
--   bucket to greet you when you walk up, and he bounces and nods while he's talking to you.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Dialog
task.spawn(function()
	local ok, mod = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("FishClient"):WaitForChild("Dialog"))
	end)
	if ok then
		Dialog = mod
	end
end)

local LOOK_RANGE = 26 -- studs: he watches you inside this
local GREET_RANGE = 16 -- he lifts his bucket to say hi when you come this close
local zorps = {}

local function setup(z: Model)
	local pivot = z:GetPivot()
	local scale = z:GetScale()
	local st = { model = z, pivot = pivot, scale = scale, pieces = {}, phase = math.random() * 10 }
	for _, piece in z:GetChildren() do
		if piece:IsA("Model") and piece.Name:find("^Zorp") then
			local parts = {}
			for _, p in piece:GetDescendants() do
				if p:IsA("BasePart") then
					table.insert(parts, { part = p, rest = pivot:ToObjectSpace(p.CFrame), size = p.Size })
				end
			end
			if #parts == 0 then
				return nil -- still loading on this client: try again on the next scan
			end
			local j = piece:GetAttribute("Joint")
			st.pieces[piece.Name] = { parts = parts, joint = if j then j * scale else Vector3.zero, model = piece }
		end
	end
	if not st.pieces.ZorpHead then
		return nil
	end
	st.yaw, st.pitch = 0, 0
	st.antL, st.antR = { x = 0, v = 0 }, { x = 0, v = 0 }
	st.blinkAt = os.clock() + 1 + math.random() * 3
	st.greet = -10
	st.near = false
	return st
end

local function scan()
	for z, st in zorps do
		-- gone, or some of his parts were streamed out and back in: start over
		local stale = not z.Parent
		for _, piece in st.pieces do
			local count = 0
			for _, d in piece.model:GetDescendants() do
				if d:IsA("BasePart") then
					count += 1
				end
			end
			if count ~= #piece.parts then
				stale = true
			end
			for _, e in piece.parts do
				if not e.part.Parent then
					stale = true
				end
			end
		end
		if stale then
			-- put his parts back to rest first, so the next setup doesn't mistake a pose for his rest position
			for _, piece in st.pieces do
				for _, e in piece.parts do
					if e.part.Parent then
						e.part.CFrame = st.pivot * e.rest
						e.part.Size = e.size
					end
				end
			end
			zorps[z] = nil
		end
	end
	for _, z in workspace:GetDescendants() do
		if z.Name == "QuestAlien" and z:IsA("Model") and z:GetAttribute("Animated") and not zorps[z] then
			local st = setup(z)
			if st then
				zorps[z] = st
			end
		end
	end
end
task.spawn(function()
	while true do
		scan()
		task.wait(2)
	end
end)

local function around(joint: Vector3, cf: CFrame): CFrame
	return CFrame.new(joint) * cf * CFrame.new(-joint)
end

local function place(piece, cf: CFrame, pivot: CFrame)
	for _, e in piece.parts do
		e.part.CFrame = pivot * cf * e.rest
	end
end

-- the Zorp you're talking to is the nearest one while the talk box is open
local function nearestZorp(pos: Vector3)
	local best, bd
	for z, st in zorps do
		local d = (st.pivot.Position - pos).Magnitude
		if not bd or d < bd then
			best, bd = st, d
		end
	end
	return best, bd
end

local function frame(dt)
	dt = math.min(dt, 0.05)
	local now = os.clock()
	local cam = workspace.CurrentCamera
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local headPos = char and char:FindFirstChild("Head") and (char.Head :: BasePart).Position or (root and root.Position)
	local talkingTo = nil
	if Dialog and Dialog.isOpen() and root then
		talkingTo = nearestZorp(root.Position)
	end
	for z, st in zorps do
		if not z.Parent or (cam and (cam.CFrame.Position - st.pivot.Position).Magnitude > 220) then
			continue
		end
		local t = now + st.phase
		local s = st.scale
		local P = st.pivot
		local talking = talkingTo == st
		-- where the player is, in Zorp's own space (he faces +Z)
		local wantYaw, wantPitch = 0, 0
		local dist = math.huge
		if headPos then
			local lp = P:PointToObjectSpace(headPos)
			dist = Vector3.new(lp.X, 0, lp.Z).Magnitude
			if dist < LOOK_RANGE * s / 1.25 and lp.Z > -2 then
				wantYaw = math.clamp(math.atan2(lp.X, lp.Z), -0.9, 0.9)
				wantPitch = math.clamp(-math.atan2(lp.Y - 4.75 * s, math.max(dist, 1)), -0.35, 0.3)
			end
		end
		-- say hi when someone walks up
		local near = dist < GREET_RANGE
		if near and not st.near and now - st.greet > 6 then
			st.greet = now
		end
		st.near = near
		-- head eases toward its target; remember how fast it turned (the antennae react to that)
		local k = 1 - math.exp(-dt * 5)
		local oldYaw = st.yaw
		st.yaw += (wantYaw - st.yaw) * k
		st.pitch += (wantPitch - st.pitch) * k
		local yawVel = (st.yaw - oldYaw) / math.max(dt, 1e-3)

		-- whole body: lazy sway about the feet, breathing, and a happy bounce while talking
		local body = CFrame.Angles(0, 0, math.sin(t * 0.9) * 0.018)
		local breathe = math.sin(t * 1.9) * 0.05 * s
		local hop = if talking then math.abs(math.sin(t * 8.5)) * 0.16 * s else 0
		local upper = body * CFrame.new(0, breathe + hop, 0)

		-- head: look at you, with a nod and tilt while he talks
		local nod = if talking then math.sin(t * 7) * 0.07 else math.sin(t * 0.7) * 0.02
		local tilt = if talking then math.sin(t * 3.1) * 0.06 else math.sin(t * 0.5) * 0.04
		local headCF = upper * around(st.pieces.ZorpHead.joint, CFrame.Angles(st.pitch + nod, st.yaw, tilt))

		-- antennae: springy, swinging the other way when the head turns or bounces
		for _, a in { { st.antL, "ZorpAntennaL", 1 }, { st.antR, "ZorpAntennaR", -1 } } do
			local sp = a[1]
			local target = -yawVel * 0.12 + math.sin(t * 2.2 + a[3]) * 0.09 + (if talking then math.sin(t * 13 + a[3]) * 0.12 else 0)
			sp.v += ((target - sp.x) * 90 - sp.v * 9) * dt
			sp.x += sp.v * dt
			local piece = st.pieces[a[2]]
			if piece then
				place(piece, headCF * around(piece.joint, CFrame.Angles(math.sin(t * 1.7 + a[3]) * 0.08, 0, sp.x * a[3])), P)
			end
		end
		place(st.pieces.ZorpHead, headCF, P)

		-- eyes ride on the head and blink now and then (squash them flat for a moment)
		local eyes = st.pieces.ZorpEyes
		if eyes then
			if now > st.blinkAt + 0.14 then
				st.blinkAt = now + 2 + math.random() * 3.5
			end
			local b = now - st.blinkAt
			local open = if b >= 0 and b < 0.14 then math.max(0.08, math.abs(b - 0.07) / 0.07) else 1
			for _, e in eyes.parts do
				local want = Vector3.new(e.size.X, e.size.Y * open, e.size.Z)
				if e.part.Size ~= want then
					e.part.Size = want
				end
			end
			place(eyes, headCF, P)
		end

		-- rod arm: the rod bobs gently (as if waiting for a bite)
		local armR = st.pieces.ZorpArmR
		if armR then
			local cf = upper * around(armR.joint, CFrame.Angles(math.sin(t * 1.3) * 0.05 + math.sin(t * 3.1) * 0.015, 0, math.sin(t * 0.8) * 0.02))
			place(armR, cf, P)
			if st.pieces.ZorpRod then
				place(st.pieces.ZorpRod, cf, P)
			end
		end
		-- bucket arm: hangs and swings a little; lifts the bucket and gives it a happy shake to greet you
		local armL = st.pieces.ZorpArmL
		if armL then
			local g = now - st.greet
			local lift = if g < 1.8 then math.sin(math.clamp(g / 1.8, 0, 1) * math.pi) * 0.9 else 0
			local shake = lift * math.sin(g * 16) * 0.18
			local cf = upper * around(armL.joint, CFrame.Angles(math.sin(t * 1.1) * 0.03 - lift * 0.35, 0, lift + shake + math.sin(t * 0.9) * 0.02))
			place(armL, cf, P)
			if st.pieces.ZorpBucket then
				place(st.pieces.ZorpBucket, cf, P)
			end
		end
		place(st.pieces.ZorpBody, body, P)
	end
end
RunService.RenderStepped:Connect(function(dt)
	frame(dt)
end)
