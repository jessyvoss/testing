-- Fish in Space analytics: repeating funnels (Upgrades, RobuxShop, ZorpQuest, Rebirth).
-- Each attempt is a funnel session with its own id; every step is logged at most once per session (repeats would
-- only burn the rate limit). Custom fields belong on step 1: the dashboard segments by the first step's values.
-- (AnalyticsService only sends from a published game's server; Studio play tests are no-ops.)
local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Funnels = {}

-- the step names, by funnel (numbers are permanent: add new ones rather than renumbering)
Funnels.STEPS = {
	Upgrades = { "Opened Upgrades", "Bought an Upgrade" },
	RobuxShop = { "Opened Shop", "Purchase Prompt Shown", "Purchase Completed" },
	ZorpQuest = { "Quest Accepted", "Quest Fish Caught", "Quest Turned In" },
	Rebirth = { "Reached The Void", "Can Afford Rebirth", "Rebirthed" },
}

local sessions = {} -- [funnelName] = { [player] = { id = string, done = { [step] = true } } }

local function log(player, funnelName, s, step, customFields)
	if s.done[step] then
		return
	end
	local name = Funnels.STEPS[funnelName] and Funnels.STEPS[funnelName][step]
	if not name then
		warn(("Funnels: unknown step %s %s"):format(funnelName, tostring(step)))
		return
	end
	s.done[step] = true
	local ok, err = pcall(AnalyticsService.LogFunnelStepEvent, AnalyticsService, player, funnelName, s.id, step, name, customFields)
	if not ok then
		warn("Funnel analytics: " .. tostring(err))
	end
end

-- start a new attempt (a GUID by default, or a stable id such as userId .. ":" .. rebirthNumber) and log step 1
function Funnels.start(player: Player, funnelName: string, sessionId: string?, customFields)
	sessions[funnelName] = sessions[funnelName] or {}
	local s = { id = sessionId or HttpService:GenerateGUID(false), done = {} }
	sessions[funnelName][player] = s
	log(player, funnelName, s, 1, customFields)
	return s.id
end

-- start only if this exact session isn't already running (for stable ids)
function Funnels.ensure(player: Player, funnelName: string, sessionId: string, customFields)
	local bucket = sessions[funnelName]
	local s = bucket and bucket[player]
	if s and s.id == sessionId then
		return
	end
	Funnels.start(player, funnelName, sessionId, customFields)
end

-- log a later step of the player's current attempt (ignored when there is no attempt running)
function Funnels.step(player: Player, funnelName: string, step: number, customFields)
	local bucket = sessions[funnelName]
	local s = bucket and bucket[player]
	if not s then
		return
	end
	log(player, funnelName, s, step, customFields)
end

function Funnels.hasSession(player: Player, funnelName: string): boolean
	return sessions[funnelName] ~= nil and sessions[funnelName][player] ~= nil
end

function Funnels.finish(player: Player, funnelName: string)
	if sessions[funnelName] then
		sessions[funnelName][player] = nil
	end
end

Players.PlayerRemoving:Connect(function(player)
	for _, bucket in sessions do
		bucket[player] = nil
	end
end)

return Funnels
