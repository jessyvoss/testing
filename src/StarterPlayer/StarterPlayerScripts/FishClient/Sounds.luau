-- Fish in Space: every sound effect in one place, so they all feel the same: soft, warm and satisfying.
-- They play through the SFX sound group (the Settings "Sound Effects" slider), which also gets a gentle
-- treble roll-off and a touch of reverb so nothing is harsh. Swap any id here to change a sound everywhere.
--   Sounds.play(name, { volume = 0..1, pitch = 1, vary = 0.05 })
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Sounds = {}
Sounds.LIST = {
	-- name      = { id, volume, pitch }
	click      = { "rbxassetid://9125746460", 0.35, 1.15 }, -- light hollow tock (Pro Sound Effects)
	talk       = { "rbxassetid://9125746460", 0.3, 1.0 },   -- the same tock, pitched up per letter: character babble
	open       = { "rbxassetid://9125746460", 0.28, 0.85 }, -- same, lower: a menu opening
	cast       = { "rbxassetid://9120669145", 0.22, 0.85 }, -- soft whip swish
	splash     = { "rbxassetid://9119480292", 0.45, 1.0 },  -- small wet slosh and drips
	catch      = { "rbxassetid://9125409791", 0.55, 1.0 },  -- small underwater bubble pop
	sparkle    = { "rbxassetid://9039611435", 0.35, 1.0 },  -- soothing harp sting (APM, Ethereal Harp Moods)
	coin       = { "rbxassetid://9119933506", 0.9, 1.05 }, -- soft ceramic ting on a saucer (Pro Sound Effects)
}

local group = SoundService:FindFirstChild("SFX") or Instance.new("SoundGroup")
group.Name = "SFX"
group.Parent = SoundService
if not group:FindFirstChild("Mellow") then
	local eq = Instance.new("EqualizerSoundEffect")
	eq.Name = "Mellow"
	eq.HighGain = -7 -- round off anything sharp
	eq.MidGain = -1.5
	eq.LowGain = 1.5
	eq.Parent = group
	local verb = Instance.new("ReverbSoundEffect")
	verb.Name = "Air"
	verb.DecayTime = 1.2
	verb.Density = 0.8
	verb.Diffusion = 0.9
	verb.DryLevel = 0
	verb.WetLevel = -14
	verb.Parent = group
end

local templates = {}
local holder = Instance.new("Folder")
holder.Name = "SfxTemplates"
holder.Parent = SoundService
for name, s in Sounds.LIST do
	local snd = Instance.new("Sound")
	snd.Name = name
	snd.SoundId = s[1]
	snd.Volume = s[2]
	snd.PlaybackSpeed = s[3]
	snd.SoundGroup = group
	snd.Parent = holder
	templates[name] = snd
end
task.spawn(function()
	local list = {}
	for _, snd in templates do
		table.insert(list, snd)
	end
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync(list)
	end)
end)

local last = {}
function Sounds.play(name: string, opts: { volume: number?, pitch: number?, vary: number? }?)
	local t = templates[name]
	if not t then
		return
	end
	-- the same sound can't stack up into a wall of noise
	local now = os.clock()
	if last[name] and now - last[name] < 0.035 then
		return
	end
	last[name] = now
	local s = t:Clone()
	local vary = (opts and opts.vary) or 0.04
	s.Volume = t.Volume * ((opts and opts.volume) or 1)
	s.PlaybackSpeed = t.PlaybackSpeed * ((opts and opts.pitch) or 1) * (1 + (math.random() * 2 - 1) * vary)
	s.Parent = holder
	s:Play()
	Debris:AddItem(s, 6)
end

return Sounds
