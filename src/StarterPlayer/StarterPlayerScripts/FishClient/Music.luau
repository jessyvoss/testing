-- Fish in Space: background music. Shuffles the island or sea playlist from Config.MUSIC and
-- crossfades between them when you start or stop fishing. Can be muted from the HUD.
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("FishInSpace"):WaitForChild("Config"))

local Music = {}
local M = Config.MUSIC or { island = {}, sea = {}, volume = 0.35 }
local current: Sound? = nil
local mode = "island"
local muted = false
local mult = 1 -- music volume from Settings (0..1)
local gain = 1 -- this track's loudness correction (Config.MUSIC entries are { id, gain })
local index = { island = 0, sea = 0 }
local order = { island = {}, sea = {} }

local function shuffle(list)
	local t = table.clone(list)
	for i = #t, 2, -1 do
		local j = math.random(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

local function fadeOut(s: Sound)
	local tw = TweenService:Create(s, TweenInfo.new(1.6), { Volume = 0 })
	tw:Play()
	tw.Completed:Connect(function()
		s:Destroy()
	end)
end

local playNext
playNext = function()
	local list = M[mode] or {}
	if #list == 0 then
		list = M.island or {}
	end
	if #list == 0 then
		return
	end
	if #order[mode] ~= #list or index[mode] >= #order[mode] then
		order[mode] = shuffle(list)
		index[mode] = 0
	end
	index[mode] += 1
	local entry = order[mode][index[mode]]
	local id = if typeof(entry) == "table" then entry[1] else entry
	gain = if typeof(entry) == "table" then (entry[2] or 1) else 1
	local s = Instance.new("Sound")
	s.Name = "Music"
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = 0
	s.Parent = SoundService
	if current then
		fadeOut(current)
	end
	current = s
	s:Play()
	TweenService:Create(s, TweenInfo.new(2), { Volume = if muted then 0 else M.volume * mult * gain }):Play()
	s.Ended:Connect(function()
		if current == s then
			playNext()
		end
	end)
end

function Music.start()
	playNext()
end

function Music.setMode(m: string)
	if m == mode then
		return
	end
	local same = M[m] == M[mode]
	if same then
		-- same playlist: carry on with the song that's playing
		order[m], index[m] = order[mode], index[mode]
		mode = m
		return
	end
	mode = m
	if #(M[m] or {}) > 0 then
		playNext()
	end
end

function Music.toggle(): boolean
	muted = not muted
	if current then
		TweenService:Create(current, TweenInfo.new(0.4), { Volume = if muted then 0 else M.volume * mult * gain }):Play()
	end
	return muted
end

function Music.setVolume(v: number)
	mult = math.clamp(v, 0, 1)
	if current then
		TweenService:Create(current, TweenInfo.new(0.25), { Volume = if muted then 0 else M.volume * mult * gain }):Play()
	end
end

function Music.hasTracks(): boolean
	return #(M.island or {}) + #(M.sea or {}) > 0
end

return Music
