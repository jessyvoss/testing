-- Fish in Space: talk box for characters (Zorp). A rounded speech box pops up with a name tag, the words type
-- out letter by letter with a little babble blip per letter (pitch follows the letters, so it sounds like
-- chatter), and a bobbing arrow shows when a line is done.
--   Dialog.say(who, { "line", "line", ... }, opts?)   -- lines queue up; the box closes after the last one
-- Click / tap / Space / Enter: finish the line, then go to the next. Lines also move on by themselves.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Ui = require(script.Parent:WaitForChild("Ui"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local Dialog = {}
local VOICES = {
	-- each character's voice: pitch (1 = 440 Hz), how far each syllable slides up, and how fast it warbles
	Zorp = { pitch = 1.35, slide = 0.22, warble = 22 },
}

-- Alien voice: a pure sine tone (440 Hz) played as tiny syllables. Each one slides up in pitch ("bwip") and
-- warbles (tremolo), so it sounds like a little theremin talking. Pitch follows the letters.
local SINE = "rbxassetid://80768358891915" -- 440 Hz sine tone
local voiceTemplate = Instance.new("Sound")
voiceTemplate.Name = "Voice"
voiceTemplate.SoundId = SINE
voiceTemplate.Volume = 0
voiceTemplate.Looped = true
task.defer(function()
	voiceTemplate.SoundGroup = game:GetService("SoundService"):FindFirstChild("SFX")
end)
do
	local trem = Instance.new("TremoloSoundEffect")
	trem.Name = "Warble"
	trem.Depth = 0.55
	trem.Frequency = 22
	trem.Duty = 0.6
	trem.Parent = voiceTemplate
	local eq = Instance.new("EqualizerSoundEffect") -- soften the pure tone a little
	eq.HighGain = -6
	eq.LowGain = 2
	eq.Parent = voiceTemplate
end
voiceTemplate.Parent = game:GetService("SoundService")
pcall(function()
	game:GetService("ContentProvider"):PreloadAsync({ voiceTemplate })
end)

local function syllable(pitch: number, voice)
	local s = voiceTemplate:Clone()
	s.Name = "talk"
	local w = s:FindFirstChild("Warble")
	if w then
		w.Frequency = voice.warble or 22
	end
	s.PlaybackSpeed = pitch * (1 - (voice.slide or 0.2) / 2)
	s.Parent = voiceTemplate.Parent
	s.TimePosition = 0.05
	s:Play()
	local life = 0.085
	-- quick fade in, slide up, fade out
	TweenService:Create(s, TweenInfo.new(0.012), { Volume = 0.32 }):Play()
	TweenService:Create(s, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { PlaybackSpeed = pitch * (1 + (voice.slide or 0.2) / 2) }):Play()
	task.delay(life * 0.55, function()
		TweenService:Create(s, TweenInfo.new(life * 0.45), { Volume = 0 }):Play()
	end)
	task.delay(life + 0.05, function()
		s:Destroy()
	end)
end

local gui = Ui.gui("Dialog", 35)
local Art = Ui.Art
-- the box is built from the game's UI kit: the same holo panel, dark inner fill, corner brackets and fonts as the menus
local holder = Ui.frame(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(660, 160), Visible = false })
local fit = Instance.new("UIScale")
fit.Parent = holder
local inner = Ui.frame(holder, { Name = "Inner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1) })
local pop = Instance.new("UIScale") -- the pop-in bounce (the holder's own UIScale fits the screen)
pop.Name = "Pop"
pop.Parent = inner
local panel = Ui.panel(inner, { Name = "Box", Size = UDim2.fromScale(1, 1) })
do
	local fill = Ui.frame(panel, { Name = "Fill", BackgroundTransparency = 0.12, BackgroundColor3 = Color3.fromRGB(26, 18, 58), Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 1, -24), ZIndex = 1 })
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = fill
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(150, 150, 170)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 70, 90)),
	})
	g.Parent = fill
	local rim = Ui.frame(fill, { Name = "Rim", BackgroundTransparency = 0.55, BackgroundColor3 = Color3.fromRGB(200, 185, 255), Position = UDim2.fromOffset(18, 1), Size = UDim2.new(1, -36, 0, 2) })
	local rg = Instance.new("UIGradient")
	rg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	rg.Parent = rim
		end
local text = Ui.label(panel, {
	Name = "Text",
	Text = "",
	Font = Ui.TECH,
	TextSize = 25,
	TextColor3 = Ui.TEXT,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Position = UDim2.fromOffset(40, 46),
	Size = UDim2.new(1, -96, 1, -64),
	ZIndex = 3,
})
do
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(8, 4, 24)
	st.Thickness = 1.5
	st.Transparency = 0.4
	st.Parent = text
end
-- clicking anywhere on the box moves the talk along
local box = Instance.new("TextButton")
box.Name = "Hit"
box.Text = ""
box.BackgroundTransparency = 1
box.Size = UDim2.fromScale(1, 1)
box.ZIndex = 5
box.Parent = panel
-- name plate: a chunky rounded purple tag hanging off the top-left corner
local plate = Instance.new("ImageLabel")
plate.Name = "NamePlate"
plate.Image = ""
plate.BackgroundTransparency = 0
plate.BackgroundColor3 = Color3.new(1, 1, 1)
plate.BorderSizePixel = 0
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 12)
	c.Parent = plate
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.fromRGB(160, 110, 255), Color3.fromRGB(112, 66, 222))
	g.Parent = plate
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(24, 14, 52)
	st.Thickness = 2.5
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = plate
end
plate.Size = UDim2.fromOffset(150, 40)
plate.Position = UDim2.fromOffset(30, -20)
plate.ZIndex = 6
plate.Parent = inner
local tag = Ui.label(plate, { Name = "Name", Text = "", Font = Ui.TITLE, TextSize = 18, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 7 })
do
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(8, 4, 24)
	st.Thickness = 1.5
	st.Transparency = 0.3
	st.Parent = tag
end
local arrow = Ui.label(panel, { Name = "Next", Text = "▼", Font = Ui.TITLE, TextSize = 20, TextColor3 = Ui.CYAN, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -34, 1, -18), Size = UDim2.fromOffset(26, 26), Visible = false, ZIndex = 4 })

local function resize()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 800)
	-- fit the width, and never take more than about a third of the screen's height (phones in landscape)
	-- and stay clear of the HUD's side buttons on the left (the box is centred, so keep that gap on both sides)
	local hudGui = Players.LocalPlayer.PlayerGui:FindFirstChild("Hud")
	local sideRight = (hudGui and hudGui:GetAttribute("SideRight")) or 0
	fit.Scale = math.clamp(math.min((vp.X - 40) / 640, (vp.X - 2 * (sideRight + 12)) / 640, vp.Y * 0.36 / 160), 0.45, 1.1)
end
task.spawn(function()
	local hudGui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Hud")
	hudGui:GetAttributeChangedSignal("SideRight"):Connect(resize)
	resize()
end)
resize()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
end

local queue = {}
local showing = false
local closedListeners = {}
local typing = false
local skip = false
local advance = false

-- while Zorp is talking, his own prompt hides (so E doesn't start the conversation over)
local function setPrompts(on: boolean)
	for _, d in workspace:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Name == "ZorpPrompt" then
			d.Enabled = on
		end
	end
end

local function blip(ch: string, voice)
	if not ch:match("%a") then
		return
	end
	-- vowels a little higher, every letter a little different: chatter, not a beep
	local b = string.byte(ch:lower())
	local vowel = ch:lower():match("[aeiouy]") ~= nil
	local pitch = voice.pitch * (1 + ((b % 7) - 3) * 0.06) * (if vowel then 1.1 else 0.95)
	syllable(pitch, voice)
end

local function open(who: string)
	local voice = VOICES[who] or { pitch = 1.5 }
	tag.Text = string.upper(who)
	holder.Visible = true
	pop.Scale = 0.6
	panel.ImageTransparency = 0.6
	TweenService:Create(pop, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(panel, TweenInfo.new(0.2), { ImageTransparency = 0 }):Play()
	plate.Position = UDim2.fromOffset(30, -34)
	TweenService:Create(plate, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(30, -20) }):Play()
	setPrompts(false)
	return voice
end

local function close()
	local t = TweenService:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.6 })
	t:Play()
	TweenService:Create(panel, TweenInfo.new(0.18), { ImageTransparency = 1 }):Play()
	t.Completed:Wait()
	holder.Visible = false
	text.Text = ""
	setPrompts(true)
end

local function run()
	showing = true
	local who = queue[1].who
	local voice = open(who)
	task.wait(0.15)
	while #queue > 0 do
		local item = table.remove(queue, 1)
		if item.who ~= who then
			who = item.who
			voice = VOICES[who] or voice
			tag.Text = string.upper(who)
		end
		-- type it out
		arrow.Visible = false
		text.Text = item.line
		text.MaxVisibleGraphemes = 0
		typing, skip, advance = true, false, false
		local n = utf8.len(item.line) or #item.line
		local i = 0
		for _, code in utf8.codes(item.line) do
			if skip then
				break
			end
			i += 1
			text.MaxVisibleGraphemes = i
			local ch = utf8.char(code)
			if i % 2 == 1 then
				blip(ch, voice)
			end
			local pause = 0.032
			if ch:match("[%.!%?~]") then
				pause = 0.2
			elseif ch == "," then
				pause = 0.1
			end
			task.wait(pause)
		end
		text.MaxVisibleGraphemes = -1
		typing = false
		arrow.Visible = true
		-- wait for a click, or move on by itself after a moment
		local t0 = os.clock()
		local hold = 1.6 + n * 0.035
		while not advance and os.clock() - t0 < hold do
			task.wait()
		end
		arrow.Visible = false
	end
	close()
	showing = false
	for _, fn in closedListeners do
		task.spawn(fn)
	end
end

-- the arrow bobs while it waits
task.spawn(function()
	while true do
		local dt = task.wait()
		if arrow.Visible then
			arrow.Position = UDim2.new(1, -34, 1, -18 + math.sin(os.clock() * 7) * 3)
		end
		_ = dt
	end
end)

local function press()
	if not showing then
		return
	end
	if typing then
		skip = true
	else
		advance = true
	end
end
box.Activated:Connect(press)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.ButtonA then
		press()
	end
end)
_ = ProximityPromptService
_ = Players

function Dialog.say(who: string, lines: { string })
	for _, l in lines do
		table.insert(queue, { who = who, line = l })
	end
	if not showing then
		task.spawn(run)
	end
end

function Dialog.isOpen(): boolean
	return showing
end

-- stop talking now: drop the rest of the lines and close the box
function Dialog.stop()
	table.clear(queue)
	skip = true
	advance = true
end

-- run fn now if nobody is talking, otherwise as soon as the talk box closes
function Dialog.afterTalk(fn: () -> ())
	if not showing then
		fn()
		return
	end
	local entry
	entry = function()
		local i = table.find(closedListeners, entry)
		if i then
			table.remove(closedListeners, i)
		end
		fn()
	end
	table.insert(closedListeners, entry)
end

return Dialog
