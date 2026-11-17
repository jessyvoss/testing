-- Fish in Space: UI kit in a chunky, friendly Roblox-simulator style. Every screen is built from these pieces, so
-- the whole game shares one look: rounded navy-to-purple panels with a purple outline and a soft shadow, big rounded
-- bold white text with a dark outline, and chunky raised buttons (purple, or bright green for "go" / "buy").
-- Icons are full-colour cartoon renders (Art.icon) and are never tinted.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Art = require(ReplicatedStorage:WaitForChild("FishInSpace"):WaitForChild("Art"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local Ui = {}
Ui.Art = Art
-- text / accent colours (used all over the game)
Ui.PURPLE = Color3.fromRGB(176, 140, 255)
Ui.CYAN = Color3.fromRGB(110, 205, 255)
Ui.TEXT = Color3.fromRGB(255, 255, 255)
Ui.MUTED = Color3.fromRGB(196, 186, 240)
Ui.GOLD = Color3.fromRGB(255, 212, 72)
Ui.RED = Color3.fromRGB(255, 92, 100)
Ui.GREEN = Color3.fromRGB(110, 235, 120)
Ui.TITLE = Enum.Font.FredokaOne -- big rounded bold
Ui.TECH = Enum.Font.FredokaOne -- buttons and labels
Ui.BODY = Enum.Font.GothamMedium -- small readable text
-- surface colours
local INK = Color3.fromRGB(24, 14, 52) -- outlines and text strokes
local PANEL_TOP, PANEL_BOTTOM = Color3.fromRGB(56, 44, 118), Color3.fromRGB(34, 26, 82)
local PANEL_EDGE = Color3.fromRGB(128, 96, 232)
local PANEL_EDGE_HI = Color3.fromRGB(100, 180, 255) -- a highlighted panel
local BTN = {
	purple = { Color3.fromRGB(160, 110, 255), Color3.fromRGB(112, 66, 222), Color3.fromRGB(74, 40, 160) },
	green = { Color3.fromRGB(120, 230, 90), Color3.fromRGB(64, 180, 50), Color3.fromRGB(36, 120, 30) },
	red = { Color3.fromRGB(255, 104, 104), Color3.fromRGB(226, 52, 60), Color3.fromRGB(150, 24, 36) },
	blue = { Color3.fromRGB(110, 180, 255), Color3.fromRGB(56, 128, 240), Color3.fromRGB(30, 76, 170) },
	grey = { Color3.fromRGB(150, 146, 180), Color3.fromRGB(112, 108, 146), Color3.fromRGB(70, 66, 100) },
}

function Ui.gui(name: string, order: number?): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.DisplayOrder = order or 0
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return g
end

function Ui.frame(parent: Instance, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	for k, v in props or {} do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

local function corner(g: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = g
	return c
end
local function stroke(g: GuiObject, color: Color3, thickness: number, transp: number?, border: boolean?)
	local st = Instance.new("UIStroke")
	st.Color = color
	st.Thickness = thickness
	st.Transparency = transp or 0
	if border then
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	st.Parent = g
	return st
end
local function vgrad(g: GuiObject, top: Color3, bottom: Color3)
	local gr = Instance.new("UIGradient")
	gr.Rotation = 90
	gr.Color = ColorSequence.new(top, bottom)
	gr.Parent = g
	return gr
end

function Ui.label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = Ui.TEXT
	l.Font = Ui.TECH
	l.TextSize = 18
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in props do
		(l :: any)[k] = v
	end
	-- the rounded font runs small: give it a bit more size (screens were laid out for the old, taller font)
	if l.Font == Enum.Font.FredokaOne and not l.TextScaled and not l:GetAttribute("ExactSize") then
		l.TextSize = math.floor(l.TextSize * 1.12 + 0.5)
	end
	-- the chunky look: rounded bold text gets a dark outline so it reads on any background
	if l.Font == Enum.Font.FredokaOne and not l:FindFirstChildOfClass("UIStroke") then
		stroke(l, INK, if l.TextSize >= 22 then 2.2 else 1.4, 0.15)
	end
	l.Parent = parent
	return l
end

function Ui.image(parent: Instance, image: string, props: { [string]: any }?): ImageLabel
	local i = Instance.new("ImageLabel")
	i.BackgroundTransparency = 1
	i.Image = image
	i.ScaleType = Enum.ScaleType.Fit
	for k, v in props or {} do
		(i :: any)[k] = v
	end
	i.Parent = parent
	return i
end

-- A soft shadow under a free-standing panel (one placed straight on a ScreenGui), kept in step with it.
local function dropShadow(g: GuiObject)
	local parent = g.Parent
	if not (parent and parent:IsA("ScreenGui")) then
		return
	end
	local d = Instance.new("Frame")
	d.Name = g.Name .. "Shadow"
	d.BorderSizePixel = 0
	d.BackgroundColor3 = Color3.fromRGB(4, 0, 16)
	d.Active = false
	corner(d, 20)
	local scale = Instance.new("UIScale")
	scale.Parent = d
	local function sync()
		d.AnchorPoint = g.AnchorPoint
		d.Size = g.Size
		d.Position = g.Position + UDim2.fromOffset(0, 8)
		d.Visible = g.Visible
		d.ZIndex = g.ZIndex - 1
		d.BackgroundTransparency = 1 - 0.45 * (1 - ((g :: any).ImageTransparency or 0))
		local fit = g:FindFirstChild("Fit")
		scale.Scale = if fit and fit:IsA("UIScale") then fit.Scale else 1
	end
	sync()
	for _, prop in { "AnchorPoint", "Size", "Position", "Visible", "ZIndex", "ImageTransparency" } do
		g:GetPropertyChangedSignal(prop):Connect(sync)
	end
	g.ChildAdded:Connect(function(c)
		if c.Name == "Fit" and c:IsA("UIScale") then
			c:GetPropertyChangedSignal("Scale"):Connect(sync)
			sync()
		end
	end)
	g.AncestryChanged:Connect(function()
		if not g.Parent then
			d:Destroy()
		end
	end)
	d.Parent = parent
end

-- A rounded panel: navy-to-purple, purple outline, soft shadow. highlight = a brighter blue outline (selected/important).
function Ui.panel(parent: Instance, props: { [string]: any }?, highlight: boolean?): ImageLabel
	local p = Instance.new("ImageLabel") -- (an ImageLabel only so older code that fades ImageTransparency still works)
	p.Name = "Panel"
	p.Image = ""
	p.BackgroundTransparency = 0
	p.BackgroundColor3 = Color3.new(1, 1, 1)
	p.BorderSizePixel = 0
	for k, v in props or {} do
		(p :: any)[k] = v
	end
	corner(p, 18)
	vgrad(p, PANEL_TOP, PANEL_BOTTOM)
	stroke(p, if highlight then PANEL_EDGE_HI else PANEL_EDGE, 3, 0, true)
	p.Parent = parent
	dropShadow(p)
	-- fading the panel (Ui.pop) fades its fill too
	p:GetPropertyChangedSignal("ImageTransparency"):Connect(function()
		p.BackgroundTransparency = p.ImageTransparency
	end)
	return p
end

-- an inset, darker area inside a panel (lists, slots)
function Ui.inset(parent: Instance, props: { [string]: any }?): Frame
	local f = Ui.frame(parent, props)
	f.BackgroundTransparency = 0
	f.BackgroundColor3 = Color3.fromRGB(26, 18, 60)
	corner(f, 14)
	stroke(f, Color3.fromRGB(70, 52, 150), 2, 0.2, true)
	return f
end

local function pressable(b: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.Activated:Connect(function()
		Sounds.play("click")
	end)
	local function to(v)
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = v }):Play()
	end
	b.MouseEnter:Connect(function()
		to(1.05)
	end)
	b.MouseLeave:Connect(function()
		to(1)
	end)
	b.MouseButton1Down:Connect(function()
		to(0.95)
	end)
	b.MouseButton1Up:Connect(function()
		to(1.05)
	end)
end

-- the chunky raised look: a coloured face with a gloss on top, sitting on a darker lip that shows underneath
local function chunky(b: GuiButton, style: string, radius: number)
	local c = BTN[style] or BTN.purple
	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.BorderSizePixel = 0
	lip.BackgroundColor3 = c[3]
	lip.Position = UDim2.fromOffset(0, 5)
	lip.Size = UDim2.fromScale(1, 1)
	lip.ZIndex = 0
	corner(lip, radius)
	stroke(lip, INK, 2.5, 0, true)
	lip.Parent = b
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BorderSizePixel = 0
	face.BackgroundColor3 = Color3.new(1, 1, 1)
	face.Size = UDim2.fromScale(1, 1)
	face.ZIndex = 1
	corner(face, radius)
	local grad = vgrad(face, c[1], c[2])
	grad.Name = "Fill"
	stroke(face, INK, 2.5, 0, true)
	face.Parent = b
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BorderSizePixel = 0
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.82
	gloss.Position = UDim2.new(0, 5, 0, 4)
	gloss.Size = UDim2.new(1, -10, 0.42, 0)
	gloss.ZIndex = 1
	corner(gloss, math.max(4, radius - 4))
	gloss.Parent = face
	b:SetAttribute("Style", style)
	-- pressing pushes the face down onto the lip
	local function to(y)
		TweenService:Create(face, TweenInfo.new(0.07), { Position = UDim2.fromOffset(0, y) }):Play()
	end
	b.MouseButton1Down:Connect(function()
		to(4)
	end)
	b.MouseButton1Up:Connect(function()
		to(0)
	end)
	b.MouseLeave:Connect(function()
		to(0)
	end)
end

local function restyle(b: GuiButton, style: string)
	local c = BTN[style] or BTN.purple
	local face = b:FindFirstChild("Face")
	local lip = b:FindFirstChild("Lip")
	if face and face:FindFirstChild("Fill") then
		(face.Fill :: UIGradient).Color = ColorSequence.new(c[1], c[2])
	end
	if lip then
		(lip :: Frame).BackgroundColor3 = c[3]
	end
	b:SetAttribute("Style", style)
end

-- A chunky rounded button. primary = the bright green "go / buy" look (Ui.setActive switches it).
function Ui.button(parent: Instance, text: string, props: { [string]: any }?, primary: boolean?): ImageButton
	local b = Instance.new("ImageButton")
	b.Name = "Button"
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.Image = ""
	b.Size = UDim2.fromOffset(200, 50)
	Ui.label(b, {
		Name = "Text",
		Text = text,
		Font = Ui.TECH,
		TextSize = 22,
		TextColor3 = Ui.TEXT,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	})
	for k, v in props or {} do
		(b :: any)[k] = v
	end
	chunky(b, if primary then "green" else "purple", 14)
	-- the label rides with the face when pressed
	local face = b:FindFirstChild("Face") :: Frame
	local t = b:FindFirstChild("Text") :: TextLabel
	face:GetPropertyChangedSignal("Position"):Connect(function()
		t.Position = face.Position
	end)
	pressable(b)
	b.Parent = parent
	return b
end

-- on = the green "go" look (buy when affordable, toggles, picked options); kind "tile" = the blue "selected" look
function Ui.setActive(b: ImageButton, on: boolean, kind: string?)
	if kind == "tile" then
		restyle(b, if on then "blue" else "purple")
	else
		restyle(b, if on then "green" else "purple")
	end
end

-- a button in any colour: "purple", "green", "red", "blue" or "grey"
function Ui.setStyle(b: ImageButton, style: string)
	restyle(b, style)
end

function Ui.setText(b: Instance, text: string)
	local t = b:FindFirstChild("Text") :: TextLabel?
	if t then
		t.Text = text
	end
end

-- Square icon tile with its name under the icon (side menu, shop tabs).
function Ui.tile(parent: Instance, icon: string, text: string, props: { [string]: any }?, highlight: boolean?): ImageButton
	local b = Instance.new("ImageButton")
	b.Name = text
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.Image = ""
	b.Size = UDim2.fromOffset(84, 84)
	for k, v in props or {} do
		(b :: any)[k] = v
	end
	chunky(b, if highlight then "blue" else "purple", 18)
	local face = b:FindFirstChild("Face") :: Frame
	local hasText = text ~= ""
	-- the icon fills the tile (a little room for the label at the bottom)
	Ui.image(face, icon, { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, if hasText then 0.43 else 0.5), Size = UDim2.fromScale(if hasText then 0.84 else 0.8, if hasText then 0.84 else 0.8), ZIndex = 2 })
	if hasText then
		-- the name sits across the tile's bottom edge, big and bold with a thick black outline
		local lab = Ui.label(face, { ZIndex = 4, Name = "Label", Text = text, Font = Ui.TECH, TextSize = 17, TextColor3 = Ui.TEXT, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, 16, 0, 22) })
		local st = lab:FindFirstChildOfClass("UIStroke")
		if st then
			st.Thickness = 3
			st.Color = Color3.fromRGB(12, 8, 20)
			st.Transparency = 0
		end
	end
	-- (old code looks these up on the button itself)
	local icn = face:FindFirstChild("Icon")
	local proxy = Instance.new("ObjectValue")
	proxy.Name = "IconRef"
	proxy.Value = icn
	proxy.Parent = b
	pressable(b)
	b.Parent = parent
	return b
end

-- A button that is just the icon (no tile behind it), with its name in bold outlined text across the bottom.
-- It bobs up on hover and squashes when pressed. Used for the HUD's side menu and the settings cog.
function Ui.iconButton(parent: Instance, icon: string, text: string, props: { [string]: any }?): ImageButton
	local b = Instance.new("ImageButton")
	b.Name = text ~= "" and text or "IconButton"
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.Image = ""
	b.Size = UDim2.fromOffset(84, 84)
	for k, v in props or {} do
		(b :: any)[k] = v
	end
	-- the icon is its own child so it can bob without moving the button's hit area
	local img = Ui.image(b, icon, { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	if text ~= "" then
		local lab = Ui.label(b, { ZIndex = 4, Name = "Label", Text = text, Font = Ui.TECH, TextSize = 17, TextColor3 = Ui.TEXT, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.new(1, 16, 0, 22) })
		local st = lab:FindFirstChildOfClass("UIStroke")
		if st then
			st.Thickness = 3
			st.Color = Color3.fromRGB(12, 8, 20)
			st.Transparency = 0
		end
		img.Size = UDim2.fromScale(0.92, 0.92)
		img.Position = UDim2.fromScale(0.5, 0.44)
	end
	local base = img.Position
	local function bob(dy, rot)
		TweenService:Create(img, TweenInfo.new(0.1), { Position = base + UDim2.fromOffset(0, dy), Rotation = rot }):Play()
	end
	b.MouseEnter:Connect(function()
		bob(-4, -6)
	end)
	b.MouseLeave:Connect(function()
		bob(0, 0)
	end)
	b.MouseButton1Down:Connect(function()
		bob(2, 0)
	end)
	b.MouseButton1Up:Connect(function()
		bob(-4, -6)
	end)
	pressable(b)
	b.Parent = parent
	return b
end

-- Red dot with a number (side menu).
function Ui.badge(parent: Instance): TextLabel
	local d = Ui.label(parent, { Name = "Badge", Text = "", Font = Ui.TECH, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(240, 50, 60), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(26, 26), Visible = false, ZIndex = 8 })
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = d
	stroke(d, Color3.new(1, 1, 1), 2.5, 0, true)
	return d
end

-- A rounded bar made of chunky segments (bucket, completion, power). Returns the frame and a setter (0..1).
function Ui.meter(parent: Instance, segments: number, props: { [string]: any }, color: Color3?): (Frame, (number) -> ())
	local f = Ui.frame(parent, props)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, if segments > 12 then 2 else 4)
	list.Parent = f
	local segs = {}
	local gap = if segments > 12 then 2 else 4
	for i = 1, segments do
		local sgm = Ui.frame(f, { BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(22, 14, 50), Size = UDim2.new(1 / segments, -gap, 1, 0), LayoutOrder = i })
		corner(sgm, if segments > 12 then 3 else 6)
		local sg = Instance.new("UIGradient") -- glossy: bright top, deeper bottom
		sg.Rotation = 90
		sg.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 170, 190)),
		})
		sg.Parent = sgm
		segs[i] = sgm
	end
	local col = color or Ui.CYAN
	local function set(v: number)
		local n = math.clamp(v, 0, 1) * segments
		for i, sgm in segs do
			local on = i <= math.floor(n + 0.001)
			sgm.BackgroundColor3 = if on then col else Color3.fromRGB(22, 14, 50)
		end
	end
	set(0)
	return f, set
end

-- A centred window: a big title at the top left and a chunky red close button at the top right.
function Ui.window(parent: Instance, title: string, size: Vector2, onClose: () -> ()): ImageLabel
	local w = Ui.panel(parent, { Name = title, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size.X, size.Y), Visible = false, ZIndex = 10 })
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = size
	limit.Parent = w
	local scale = Instance.new("UIScale")
	scale.Name = "Fit"
	scale.Parent = w
	local function fit()
		local cam = workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(1280, 800)
		-- Big screens: the window is shrunk as a whole until it fits. Phones: shrinking a 640-tall window into a
		-- ~375-tall screen made text about half size (unreadable), so the window never shrinks below MIN_SCALE;
		-- instead it gets shorter/narrower itself (its lists scroll), filling the screen at a readable size.
		local MIN_SCALE = 0.72
		local small = vp.Y < 500
		local mY, mX = if small then 12 else 60, if small then 12 else 30
		local fitScale = math.min((vp.Y - mY) / size.Y, (vp.X - mX) / size.X)
		if fitScale >= MIN_SCALE then
			scale.Scale = math.min(fitScale, 1)
			w.Size = UDim2.fromOffset(size.X, size.Y)
		else
			scale.Scale = MIN_SCALE
			w.Size = UDim2.fromOffset(math.min(size.X, (vp.X - mX) / MIN_SCALE), math.min(size.Y, (vp.Y - mY) / MIN_SCALE))
		end
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	-- header strip
	local header = Ui.frame(w, { Name = "Header", BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(70, 54, 150), Size = UDim2.new(1, 0, 0, 68), ZIndex = 10 })
	corner(header, 18)
	vgrad(header, Color3.fromRGB(96, 74, 196), Color3.fromRGB(66, 50, 146))
	Ui.frame(header, { Name = "Square", BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(66, 50, 146), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 18), ZIndex = 10 })
	Ui.label(w, { Name = "Title", Text = title, Font = Ui.TITLE, TextSize = 32, TextColor3 = Ui.TEXT, Position = UDim2.fromOffset(28, 12), Size = UDim2.new(1, -120, 0, 44), ZIndex = 11 })
	local close = Instance.new("ImageButton")
	close.Name = "Close"
	close.BackgroundTransparency = 1
	close.AutoButtonColor = false
	close.Image = ""
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 10)
	close.Size = UDim2.fromOffset(46, 44)
	close.ZIndex = 12
	chunky(close, "red", 12)
	Ui.label(close:FindFirstChild("Face") :: Frame, { Name = "X", Text = "X", Font = Ui.TITLE, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	pressable(close)
	close.Parent = w
	close.Activated:Connect(onClose)
	return w
end

function Ui.pop(g: GuiObject)
	local s = (g:FindFirstChild("Pop") or Instance.new("UIScale")) :: UIScale
	if g:FindFirstChild("Fit") then
		-- windows already scale to fit: a quick bounce on top of that
		local fit = g:FindFirstChild("Fit") :: UIScale
		local target = fit.Scale
		fit.Scale = target * 0.9
		TweenService:Create(fit, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = target }):Play()
		return
	end
	s.Name = "Pop"
	s.Scale = 0.85
	s.Parent = g
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

local UserInputService = game:GetService("UserInputService")
local function round(g: GuiObject, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = if r then UDim.new(0, r) else UDim.new(1, 0)
	c.Parent = g
end

-- A 0..1 slider with a percent readout. Drag or tap anywhere on it. Returns the frame and a setter.
function Ui.slider(parent: Instance, props: { [string]: any }, value: number, onChange: (number) -> ()): (Frame, (number) -> ())
	local f = Ui.frame(parent, props)
	local track = Ui.frame(f, { Name = "Track", BackgroundTransparency = 0.55, BackgroundColor3 = Ui.PURPLE, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.new(1, -78, 0, 8) })
	round(track)
	local fill = Ui.frame(track, { Name = "Fill", BackgroundTransparency = 0.05, BackgroundColor3 = Ui.CYAN })
	round(fill)
	local knob = Ui.frame(track, { Name = "Knob", BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(210, 252, 255), AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(22, 22), ZIndex = 3 })
	round(knob)
	local ks = Instance.new("UIStroke")
	ks.Color = Ui.CYAN
	ks.Thickness = 2
	ks.Parent = knob
	local pct = Ui.label(f, { Name = "Value", Text = "", Font = Ui.TECH, TextSize = 17, TextColor3 = Ui.CYAN, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(56, 22) })
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.new(1, -60, 1, 0)
	hit.ZIndex = 4
	hit.Parent = f
	local function set(v: number)
		v = math.clamp(v, 0, 1)
		fill.Size = UDim2.fromScale(v, 1)
		knob.Position = UDim2.fromScale(v, 0.5)
		pct.Text = tostring(math.round(v * 100)) .. "%"
	end
	local dragging = false
	local function at(x: number)
		local v = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		v = math.round(v * 20) / 20 -- 5% steps
		set(v)
		onChange(v)
	end
	hit.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = true
			at(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local t = input.UserInputType
		if dragging and (t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch) then
			at(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	set(value)
	return f, set
end

-- An ON / OFF button (cyan when on). Returns the button and a setter.
function Ui.toggle(parent: Instance, props: { [string]: any }, onChange: (boolean) -> ()): (ImageButton, (boolean) -> ())
	local b = Ui.button(parent, "OFF", props)
	local on = false
	local function set(v: boolean)
		on = v
		Ui.setText(b, if v then "ON" else "OFF")
		Ui.setActive(b, v)
	end
	b.Activated:Connect(function()
		set(not on)
		onChange(on)
	end)
	return b, set
end

-- A row of buttons where one is picked: options = { {key, label}, ... }. Returns the frame and a setter.
function Ui.choice(parent: Instance, props: { [string]: any }, options: { { string } }, onChange: (string) -> ()): (Frame, (string) -> ())
	local f = Ui.frame(parent, props)
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Right
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = f
	local buttons = {}
	local function set(key: string)
		for k, b in buttons do
			Ui.setActive(b, k == key)
		end
	end
	for i, o in options do
		local b = Ui.button(f, o[2], { LayoutOrder = i, Size = UDim2.new(1 / #options, -6, 1, 0) })
		local t = b:FindFirstChild("Text") :: TextLabel
		t.TextSize = 16
		b.Activated:Connect(function()
			set(o[1])
			onChange(o[1])
		end)
		buttons[o[1]] = b
	end
	return f, set
end

function Ui.coinText(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- A fish picture for menus: a small live 3D view of the fish's model (FishInSpace.FishModels),
-- turned three-quarters so you see its side and a bit of its face. Falls back to the flat picture
-- for things without a model (junk). Returns a ViewportFrame or ImageLabel; both take ImageColor3
-- and ImageTransparency (black + see-through = an uncaught silhouette).
local FishModels = ReplicatedStorage:WaitForChild("FishInSpace"):WaitForChild("FishModels", 10)
function Ui.fish(parent: Instance, id: string, props: { [string]: any }?, yaw: number?)
	local src = FishModels and FishModels:FindFirstChild(id)
	if not src then
		return Ui.image(parent, Art.fish[id], props)
	end
	local vf = Instance.new("ViewportFrame")
	vf.BackgroundTransparency = 1
	vf.Ambient = Color3.fromRGB(170, 170, 190)
	vf.LightColor = Color3.fromRGB(255, 255, 255)
	vf.LightDirection = Vector3.new(-0.4, -1, -0.6)
	for k, v in props or {} do
		vf[k] = v
	end
	local m = src:Clone()
	-- head to the right of the frame, turned a little toward the viewer
	m:PivotTo(CFrame.Angles(0, math.rad(-90 - (yaw or 28)), 0))
	local cf, size = m:GetBoundingBox()
	m.Parent = vf
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local px = vf.AbsoluteSize
	local aspect = 2
	if props and props.Size then
		local w, h = props.Size.X.Offset, props.Size.Y.Offset
		if w > 0 and h > 0 then
			aspect = w / h
		end
	end
	local tv = math.tan(math.rad(cam.FieldOfView / 2))
	local th = tv * aspect
	local dist = math.max(size.X / 2 / th, size.Y / 2 / tv) * 1.08 + size.Z / 2
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, size.Y * 0.08, dist), cf.Position)
	cam.Parent = vf
	vf.CurrentCamera = cam
	vf.Parent = parent
	return vf
end

return Ui
