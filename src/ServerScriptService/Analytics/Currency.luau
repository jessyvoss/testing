-- Fish in Space analytics: economy events (not used yet; here so coin tracking can be added in one place later).
-- amount is always positive; endingBalance is the balance AFTER the change.
local AnalyticsService = game:GetService("AnalyticsService")
local Currency = {}

function Currency.source(player: Player, currency: string, amount: number, endingBalance: number, transactionType: string, itemSku: string?, customFields)
	pcall(AnalyticsService.LogEconomyEvent, AnalyticsService, player, Enum.AnalyticsEconomyFlowType.Source, currency, amount, endingBalance, transactionType, itemSku, customFields)
end

function Currency.sink(player: Player, currency: string, amount: number, endingBalance: number, transactionType: string, itemSku: string?, customFields)
	pcall(AnalyticsService.LogEconomyEvent, AnalyticsService, player, Enum.AnalyticsEconomyFlowType.Sink, currency, amount, endingBalance, transactionType, itemSku, customFields)
end

return Currency
