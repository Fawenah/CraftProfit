-- CraftProfit :: Blocked
-- Records the times the game blocks a protected action and names CraftProfit for it (the "CraftProfit has been
-- blocked from an action only available to the Blizzard UI" popup). The events only say which protected
-- function was blocked, not where the taint came from, so each record also notes what was on screen: the
-- tooltip and its owner, the open windows, and how long ago CraftProfit last re-drew a tooltip on Shift.
-- A chat line points at /cf blocked, which prints the records for a bug report. Nothing here changes behaviour.

local ADDON_NAME, CP = ...
local Blocked = { max = 20, noticeGap = 30 }
CP.Blocked = Blocked

local fmtDate = date or (os and os.date)
local WINDOWS = {
	{ "AuctionHouseFrame", "auction house" }, { "ProfessionsFrame", "professions" }, { "MerchantFrame", "merchant" },
	{ "ClassTrainerFrame", "trainer" }, { "MailFrame", "mail" }, { "BankFrame", "bank" }, { "TradeFrame", "trade" },
}

local function Try(fn, ...)
	local ok, v = pcall(fn, ...)
	if ok then return v end
	return nil
end

-- plain strings and numbers only: the record is saved and printed
local function Plain(v)
	if type(v) == "string" or type(v) == "number" then return v end
	return nil
end

function Blocked:Context()
	local c = {}
	c.combat = Try(function() return InCombatLockdown and InCombatLockdown() end) and true or false
	local tip = GameTooltip
	if tip and Try(function() return tip.IsShown and tip:IsShown() end) then
		c.owner = Plain(Try(function()
			local owner = tip:GetOwner()
			if not owner then return nil end
			return (owner.GetDebugName and owner:GetDebugName()) or (owner.GetName and owner:GetName())
		end)) or "?"
		if CP.Tooltip and CP.Tooltip:ShowsItem(tip) then
			c.item = Plain(Try(function()
				local data = tip.GetPrimaryTooltipData and tip:GetPrimaryTooltipData()
				if type(data) == "table" and data.id then return data.id end
				local _, link = tip:GetItem()
				return CP:ItemIDFromLink(link)
			end)) or "?"
		end
	end
	local last = CP.Tooltip and CP.Tooltip.lastRefresh
	if last and GetTime then c.shiftAgo = math.floor(GetTime() - last) end
	local open = {}
	for _, w in ipairs(WINDOWS) do
		if Try(function() local f = _G[w[1]]; return f and f.IsShown and f:IsShown() end) then open[#open + 1] = w[2] end
	end
	if #open > 0 then c.open = table.concat(open, ", ") end
	return c
end

function Blocked:Record(kind, addon, fn)
	if addon ~= ADDON_NAME then return end
	local db = CP.db
	if not db then return end
	local rec = self:Context()
	rec.t, rec.kind, rec.fn = time(), kind, Plain(fn) or "?"
	rec.version = CP.version
	rec.build = Plain(Try(function() return (select(4, GetBuildInfo())) end))
	db.blocked = db.blocked or {}
	table.insert(db.blocked, rec)
	while #db.blocked > self.max do table.remove(db.blocked, 1) end
	-- say so in chat, but not for every blocked call of a burst
	local now = GetTime and GetTime() or rec.t
	if not self.noticeAt or now - self.noticeAt >= self.noticeGap then
		self.noticeAt = now
		CP:Print("the game blocked %s and named CraftProfit. Please type |cffffffff/cf blocked|r and send what it prints to the author; it shows what was on screen when it happened.", rec.fn)
	end
end

function Blocked:Line(rec)
	local parts = { string.format("%s %s %s", fmtDate and fmtDate("%Y-%m-%d %H:%M:%S", rec.t) or tostring(rec.t), tostring(rec.fn), tostring(rec.kind)) }
	parts[#parts + 1] = string.format("v%s interface %s", tostring(rec.version), tostring(rec.build))
	parts[#parts + 1] = rec.combat and "in combat" or "not in combat"
	if rec.owner then
		parts[#parts + 1] = "tooltip on " .. tostring(rec.owner) .. (rec.item and (" (item " .. tostring(rec.item) .. ")") or " (not an item)")
	else
		parts[#parts + 1] = "no tooltip"
	end
	parts[#parts + 1] = rec.shiftAgo and ("Shift re-draw " .. rec.shiftAgo .. "s before") or "no Shift re-draw this session"
	parts[#parts + 1] = "open: " .. (rec.open or "nothing")
	return table.concat(parts, " | ")
end

function Blocked:Command(rest)
	local db = CP.db
	local list = db and db.blocked or {}
	if (rest or ""):lower() == "clear" then
		if db then db.blocked = nil end
		CP:Print("blocked-action records cleared.")
		return
	end
	if #list == 0 then
		CP:Print("no blocked actions recorded. When the game blocks an action and names CraftProfit, it is noted here.")
		return
	end
	CP:Print("%d blocked action%s recorded (newest last). /cf blocked clear empties the list.", #list, #list == 1 and "" or "s")
	for i = math.max(1, #list - 9), #list do CP:Print("  %s", self:Line(list[i])) end
end

CP:RegisterEvent("ADDON_ACTION_BLOCKED", function(_, addon, fn) Blocked:Record("blocked", addon, fn) end)
CP:RegisterEvent("ADDON_ACTION_FORBIDDEN", function(_, addon, fn) Blocked:Record("forbidden", addon, fn) end)
