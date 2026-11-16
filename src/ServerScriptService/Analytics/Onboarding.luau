-- Fish in Space analytics: the one-time new-player (onboarding) funnel.
-- Only players who haven't finished the tutorial when they join are tracked (call Onboarding.begin on join), so
-- veterans never show up as "new" when this goes live. Each step is logged at most once per player per server.
-- Steps are numbered for good: if the first-session flow changes, add new numbers, don't renumber.
-- (AnalyticsService only sends from a published game's server; Studio play tests are no-ops.)
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

local Onboarding = {}

Onboarding.STEPS = {
	[1] = "Player Joined",
	[2] = "First Cast",
	[3] = "First Fish Caught",
	[4] = "First Sale",
	[5] = "First Upgrade",
	[6] = "Tutorial Completed",
	[7] = "Reached Nebula Drift",
}

local tracked = {} -- [player] = { [step] = true } for players in their first-time flow

-- call when a player joins; isNew = they haven't finished the tutorial yet
function Onboarding.begin(player: Player, isNew: boolean)
	if not isNew then
		return
	end
	tracked[player] = {}
	Onboarding.markStep(player, 1)
end

function Onboarding.markStep(player: Player, step: number)
	local done = tracked[player]
	if not done or done[step] then
		return
	end
	local name = Onboarding.STEPS[step]
	if not name then
		warn(("Onboarding: unknown step %d"):format(step))
		return
	end
	done[step] = true
	local ok, err = pcall(AnalyticsService.LogOnboardingFunnelStepEvent, AnalyticsService, player, step, name)
	if not ok then
		warn("Onboarding analytics: " .. tostring(err))
	end
end

Players.PlayerRemoving:Connect(function(player)
	tracked[player] = nil
end)

return Onboarding
