-- Prognoza nocy na najbliższe dni: kiedy wypadają Krwawe księżyce (i inne rzadkie noce), w czasie
-- lokalnym tego komputera (u Toma: czas polski). Do zakładania Roblox Events z „Notify Me”
-- (Creator Hub → gra → Engagement → Events): wybierz kilka nocy w dobrych godzinach.
-- Uruchom z katalogu projektu:
--   lune run tools/night_forecast.luau              (7 dni, tylko Krwawe księżyce)
--   lune run tools/night_forecast.luau 3 full_moon  (3 dni, pełnie)
--   lune run tools/night_forecast.luau 2 all        (2 dni, wszystkie noce)
-- Liczy dokładnie tak jak gra (Shared/Cycle): noc = Config.Cycle.nightSeconds, potem świt.

local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local function loadModule(path: string, env: { [string]: any }): any
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = env })
	return chunk()
end
local function req(module)
	return module
end

local Config = loadModule("src/shared/Config.luau", {})
local Cycle = loadModule("src/shared/Cycle.luau", { script = { Parent = { Config = Config } }, require = req })

local days = tonumber(process.args[1]) or 7
local filter = process.args[2] or "blood_moon"

local now = os.time()
local length = Cycle.length()
local count = math.ceil(days * 86400 / length)
local DAYS = { "nd", "pn", "wt", "śr", "cz", "pt", "sb" }

print(string.format("Noce przez %d dni (%s), czas lokalny tego komputera. Noc trwa %d min.\n", days, filter, Config.Cycle.nightSeconds // 60))
local shown = 0
for _, night in Cycle.upcoming(now, count) do
	if filter == "all" or night.event.id == filter then
		local local_ = DateTime.fromUnixTimestamp(night.startsAt):toLocalTime()
		local weekday = DAYS[tonumber(DateTime.fromUnixTimestamp(night.startsAt):formatLocalTime("%w")) + 1]
		local prime = local_.hour >= 17 and local_.hour < 23
		print(string.format(
			"%s %02d.%02d  %02d:%02d  %s %-16s%s",
			weekday,
			local_.day,
			local_.month,
			local_.hour,
			local_.minute,
			night.event.icon,
			night.event.id,
			if prime then "  ← dobra pora na Event" else ""
		))
		shown += 1
	end
end
print(string.format("\nRazem: %d", shown))
