-- Fish in Space: player settings (the Settings window in Menus). Holds the values, applies them on this
-- client, and saves them to the player's profile on the server (a short moment after the last change).
--   music / sfx    volume 0..1
--   auras          "all" | "mine" | "off"   fish auras and the God Rod aura
--   lowGfx         no shadows, no lobby particles, no sun rays / depth of field
--   hidePlayers    hide other players (and their fish)
--   announce       show other players' big catches and server luck as pop-ups
--   autoTargets    the rarities Auto Fish goes after, e.g. "Rare,Epic"
--   shake          camera shake and tiny impact pauses when fish bite, fight and land
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("FishInSpace"):WaitForChild("Remotes")
local Music = require(script.Parent:WaitForChild("Music"))

local player = Players.LocalPlayer
local Settings = {}

local DEFAULTS = { music = 1, sfx = 1, auras = "all", lowGfx = false, hidePlayers = false, announce = true, autoTargets = "Common,Uncommon,Rare,Epic", shake = true }
Settings.DEFAULTS = DEFAULTS
local values = table.clone(DEFAULTS)
local listeners = {}
local loaded = false
local lastMusic = 1

-- every game sound effect plays through this group, so one slider sets them all
local sfx = SoundService:FindFirstChild("SFX") or Instance.new("SoundGroup")
sfx.Name = "SFX"
sfx.Parent = SoundService
Settings.sfxGroup = sfx

local function valid(k, v)
	local d = DEFAULTS[k]
	if d == nil or typeof(v) ~= typeof(d) then
		return false
	end
	if k == "auras" then
		return v == "all" or v == "mine" or v == "off"
	end
	return true
end

---------------------------------------------------------------- effects

local function ownerOf(inst: Instance): Player?
	local m = inst.Parent
	while m and m ~= workspace do
		if m:IsA("Model") then
			local p = Players:GetPlayerFromCharacter(m)
			if p then
				return p
			end
		end
		m = m.Parent
	end
	return nil
end

local function auraOn(inst: Instance): boolean
	if values.auras == "off" then
		return false
	end
	local owner = ownerOf(inst)
	if owner and owner ~= player and (values.auras == "mine" or values.hidePlayers) then
		return false
	end
	return true
end

local World = workspace:WaitForChild("World", 10)
local function applyOne(d: Instance)
	if d:IsA("BasePart") and d.Parent and d.Parent.Name == "AuraShells" then
		d.LocalTransparencyModifier = if auraOn(d) then 0 else 1
		return
	end
	if d:IsA("Highlight") then
		if d.Name == "AuraOutline" then
			d.Enabled = auraOn(d)
		end
		return
	end
	if not (d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Trail") or d:IsA("Beam")) then
		return
	end
	local root = d:FindFirstAncestor("Aura") or d:FindFirstAncestor("AuraFx")
	if root then
		d.Enabled = auraOn(root)
		return
	end
	-- lobby decoration (particles, trails, beams; lights stay on): off in low graphics
	if World and d:IsDescendantOf(World) and not d:IsA("Light") then
		if d:GetAttribute("SettingsOrig") == nil then
			d:SetAttribute("SettingsOrig", (d :: any).Enabled)
		end
		(d :: any).Enabled = d:GetAttribute("SettingsOrig") and not values.lowGfx
	end
end

local function applyLighting()
	if Lighting:GetAttribute("SettingsShadows") == nil then
		Lighting:SetAttribute("SettingsShadows", Lighting.GlobalShadows)
	end
	Lighting.GlobalShadows = Lighting:GetAttribute("SettingsShadows") and not values.lowGfx
	for _, e in Lighting:GetDescendants() do
		if e:IsA("SunRaysEffect") or e:IsA("DepthOfFieldEffect") then
			if e:GetAttribute("SettingsOrig") == nil then
				e:SetAttribute("SettingsOrig", e.Enabled)
			end
			e.Enabled = e:GetAttribute("SettingsOrig") and not values.lowGfx
		end
	end
end

local function applyPlayers()
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Character then
			local t = if values.hidePlayers then 1 else 0
			for _, d in p.Character:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then
					d.LocalTransparencyModifier = t
				end
			end
		end
	end
end

local function applyWorld()
	applyLighting()
	for _, d in workspace:GetDescendants() do
		applyOne(d)
	end
	applyPlayers()
end

local function applySound()
	sfx.Volume = values.sfx
	Music.setVolume(values.music)
end

-- new effects (a fish just pulled out, a player joining) follow the settings too
workspace.DescendantAdded:Connect(function(d)
	task.defer(applyOne, d)
end)
-- other players' characters keep re-showing their parts (tools, accessories), so keep them hidden
task.spawn(function()
	while true do
		task.wait(0.4)
		if values.hidePlayers then
			applyPlayers()
		end
	end
end)

---------------------------------------------------------------- saving

local saveToken = 0
local function scheduleSave()
	saveToken += 1
	local t = saveToken
	task.delay(1.5, function()
		if t == saveToken then
			pcall(Remotes.Shop.InvokeServer, Remotes.Shop, { action = "settings", settings = values })
		end
	end)
end

local function notify(k)
	for _, fn in listeners do
		task.spawn(fn, k, values[k])
	end
end

---------------------------------------------------------------- api

function Settings.get(k: string)
	return values[k]
end

function Settings.set(k: string, v: any)
	if not valid(k, v) or values[k] == v then
		return
	end
	values[k] = v
	if k == "music" or k == "sfx" then
		applySound()
	else
		applyWorld()
	end
	notify(k)
	scheduleSave()
end

function Settings.onChanged(fn: (string, any) -> ())
	table.insert(listeners, fn)
end

-- the values saved on your profile (only the first time the profile arrives)
function Settings.load(t)
	if loaded then
		return
	end
	loaded = true
	if typeof(t) == "table" then
		for k in DEFAULTS do
			if valid(k, t[k]) then
				values[k] = t[k]
			end
		end
	end
	applySound()
	applyWorld()
	for k in DEFAULTS do
		notify(k)
	end
end

function Settings.reset()
	values = table.clone(DEFAULTS)
	applySound()
	applyWorld()
	for k in DEFAULTS do
		notify(k)
	end
	scheduleSave()
end

-- M key: music off, or back to where it was
function Settings.toggleMusic(): boolean
	if values.music > 0 then
		lastMusic = values.music
		Settings.set("music", 0)
		return false
	end
	Settings.set("music", if lastMusic > 0 then lastMusic else 1)
	return true
end

applySound()
return Settings
