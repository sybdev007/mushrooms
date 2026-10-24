--!strict
-- Tłumaczenia z tabeli GameStrings (src/localization/GameStrings.csv -> LocalizationService).
-- Czytamy wpisy tabeli bezpośrednio przez GetEntries zamiast przez Translator Robloxa:
-- Translator w Studio potrafi po cichu zawieść i wtedy na ekranie lądowały same klucze.
-- Domyślny język bierzemy z konta gracza, przycisk w HUD przełącza EN/PL.

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")

local Localize = {}

type Entry = {
	source: string,
	values: { [string]: string },
}

local SUPPORTED = { en = true, pl = true }
local TABLE_NAME = "GameStrings"

local entries: { [string]: Entry } = {}
local currentLocale = "en"
local listeners: { () -> () } = {}

local function loadEntries()
	local stringsTable = LocalizationService:WaitForChild(TABLE_NAME, 10)
	if not (stringsTable and stringsTable:IsA("LocalizationTable")) then
		warn("[Localize] Brak tabeli " .. TABLE_NAME .. " w LocalizationService, teksty będą kluczami")
		return
	end
	for _, entry in stringsTable:GetEntries() do
		local values: { [string]: string } = {}
		for locale, text in entry.Values do
			-- "pl-pl" i "pl" traktujemy tak samo
			values[string.lower(string.sub(locale, 1, 2))] = text
		end
		entries[entry.Key] = { source = entry.Source, values = values }
	end
end

local function detectLocale(): string
	local id = Players.LocalPlayer.LocaleId
	if id == nil or id == "" then
		id = LocalizationService.RobloxLocaleId
	end
	local short = string.lower(string.sub(id, 1, 2))
	return if SUPPORTED[short] then short else "en"
end

loadEntries()
currentLocale = detectLocale()

-- Podstawia argumenty za {1}, {2}... Brakujący argument zostaje jako {n}, żeby było go widać.
local function format(text: string, args: { any }?): string
	if not args then
		return text
	end
	return (string.gsub(text, "{(%d+)}", function(index)
		local value = args[tonumber(index) :: number]
		return if value ~= nil then tostring(value) else nil
	end))
end

-- Tekst dla klucza w bieżącym języku. Gdy brak tłumaczenia, angielski; gdy brak wpisu, sam klucz.
function Localize.t(key: string, args: { any }?): string
	local entry = entries[key]
	if not entry then
		return key
	end
	local text = if currentLocale == "en" then entry.source else (entry.values[currentLocale] or entry.source)
	return format(text, args)
end

function Localize.getLocale(): string
	return currentLocale
end

function Localize.toggle()
	currentLocale = if currentLocale == "pl" then "en" else "pl"
	for _, callback in listeners do
		task.spawn(callback)
	end
end

function Localize.onChanged(callback: () -> ())
	table.insert(listeners, callback)
end

return Localize
