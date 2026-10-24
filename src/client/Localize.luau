--!strict
-- Tłumaczenia z tabeli GameStrings (src/localization/GameStrings.csv).
-- Domyślnie język z ustawień gracza, a przycisk w HUD przełącza EN/PL.

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")

local Localize = {}

local translator: Translator? = nil
local currentLocale = "en"
local listeners: { () -> () } = {}

local function loadTranslator(locale: string?)
	local ok, result = pcall(function()
		if locale then
			return LocalizationService:GetTranslatorForLocaleAsync(locale)
		end
		return LocalizationService:GetTranslatorForPlayerAsync(Players.LocalPlayer)
	end)
	if ok and result then
		translator = result
		currentLocale = string.sub(result.LocaleId, 1, 2)
	else
		warn("[Localize] Nie udało się wczytać tłumaczeń:", result)
	end
end

loadTranslator(nil)

-- Tekst dla klucza. Argumenty podstawiane są za {1}, {2}...
function Localize.t(key: string, args: { any }?): string
	local active = translator
	if active then
		local ok, text = pcall(function()
			return active:FormatByKey(key, args or {})
		end)
		if ok then
			return text
		end
	end
	return key
end

function Localize.getLocale(): string
	return currentLocale
end

function Localize.toggle()
	loadTranslator(if currentLocale == "pl" then "en" else "pl")
	for _, callback in listeners do
		task.spawn(callback)
	end
end

function Localize.onChanged(callback: () -> ())
	table.insert(listeners, callback)
end

return Localize
