-- Fish in Space: the three lobby leaderboards (top 5 each).
--   Total Coins   - coins earned
--   Biggest Fish  - the most valuable single fish caught
--   Total Catches - fish caught
-- Each player's totals are saved to OrderedDataStores; the top 5 are read once a minute.
-- If DataStores are unavailable (Studio without API access) the boards show the players in this server.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local folder = workspace:WaitForChild("World"):FindFirstChild("Leaderboards", true)
if not folder then
	return
end

local BOARDS = {
	{ board = "TotalCoins", key = "Earned", store = "FIS_TopEarned_v1" },
	{ board = "BiggestFish", key = "Biggest", store = "FIS_TopBiggest_v1" },
	{ board = "TotalCatches", key = "TotalCaught", store = "FIS_TopCaught_v1" },
}
local stores = {}
for _, st in BOARDS do
	local ok, ods = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, st.store)
	stores[st.key] = if ok then ods else nil
end

local nameCache = {}
local function nameOf(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		nameCache[userId] = p.DisplayName
		return p.DisplayName
	end
	local ok, n = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	nameCache[userId] = if ok and n then n else "Player"
	return nameCache[userId]
end

local function short(n: number): string
	if n >= 1e9 then
		return ("%.1fB"):format(n / 1e9)
	elseif n >= 1e6 then
		return ("%.1fM"):format(n / 1e6)
	elseif n >= 1e4 then
		return ("%.1fK"):format(n / 1e3)
	end
	local s = tostring(math.floor(n))
	local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (r)
end

local function draw(boardName: string, entries)
	local m = folder:FindFirstChild(boardName)
	local bg = m and m:FindFirstChild("Screen") and m.Screen:FindFirstChild("Display") and m.Screen.Display:FindFirstChild("Bg")
	if not bg then
		return
	end
	for r = 1, 5 do
		local row = bg:FindFirstChild("Row" .. r)
		if row then
			local e = entries[r]
			-- (FindFirstChild: a child called "Name" clashes with the row's own Name property)
			local nameL = row:FindFirstChild("Name") :: TextLabel
			local valueL = row:FindFirstChild("Value") :: TextLabel
			nameL.Text = if e then e.name else "-"
			valueL.Text = if e then short(e.value) else ""
		end
	end
end

local function liveTop(key: string)
	local list = {}
	for _, p in Players:GetPlayers() do
		table.insert(list, { name = p.DisplayName, value = tonumber(p:GetAttribute(key)) or 0 })
	end
	table.sort(list, function(a, b)
		return a.value > b.value
	end)
	return list
end

local function saveOne(p: Player)
	for _, st in BOARDS do
		local v = tonumber(p:GetAttribute(st.key))
		local ods = stores[st.key]
		if ods and v and v > 0 then
			pcall(ods.SetAsync, ods, tostring(p.UserId), math.floor(v))
		end
	end
end

local cached = {}
local function refresh(useStores: boolean)
	for _, st in BOARDS do
		local entries = cached[st.key]
		local ods = stores[st.key]
		if useStores and ods then
			local ok, pages = pcall(ods.GetSortedAsync, ods, false, 5)
			if ok and pages then
				entries = {}
				for _, item in pages:GetCurrentPage() do
					table.insert(entries, { name = nameOf(tonumber(item.key) or 0), value = item.value })
				end
				cached[st.key] = if #entries > 0 then entries else nil
			end
		end
		if not entries or #entries == 0 then
			entries = liveTop(st.key)
		end
		draw(st.board, entries)
	end
end

Players.PlayerRemoving:Connect(saveOne)

task.wait(5)
local tick = 0
while true do
	if tick % 6 == 0 then
		for _, p in Players:GetPlayers() do
			saveOne(p)
		end
		refresh(true)
	else
		refresh(false) -- quick in-server refresh between the once-a-minute reads
	end
	tick += 1
	task.wait(10)
end
