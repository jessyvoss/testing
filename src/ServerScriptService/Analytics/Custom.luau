-- Fish in Space analytics: custom events (not used yet). Batch frequent counters with bump(); they flush every
-- 30 s and when the player leaves, to stay under the rate limit.
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

local Custom = {}

function Custom.log(player: Player, eventName: string, value: number?, customFields)
	pcall(AnalyticsService.LogCustomEvent, AnalyticsService, player, eventName, value, customFields)
end

local pending = {} -- [player] = { [eventName] = { value = n, fields = ... } }
local FLUSH_INTERVAL = 30

function Custom.bump(player: Player, eventName: string, customFields)
	pending[player] = pending[player] or {}
	local bucket = pending[player][eventName]
	if not bucket then
		bucket = { value = 0, fields = customFields }
		pending[player][eventName] = bucket
	end
	bucket.value += 1
end

local function flush(player)
	local buckets = pending[player]
	if not buckets then
		return
	end
	pending[player] = nil
	for eventName, bucket in buckets do
		pcall(AnalyticsService.LogCustomEvent, AnalyticsService, player, eventName, bucket.value, bucket.fields)
	end
end

task.spawn(function()
	while true do
		task.wait(FLUSH_INTERVAL)
		for player in pending do
			flush(player)
		end
	end
end)

Players.PlayerRemoving:Connect(flush)

return Custom
