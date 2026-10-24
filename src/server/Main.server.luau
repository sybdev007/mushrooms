--!strict
-- Punkt startowy serwera: zbuduj mapę, potem odpal pętlę gry.

local MapBuilder = require(script.Parent.MapBuilder)
local GameService = require(script.Parent.GameService)

local map = MapBuilder.build()
GameService.start(map)

print(string.format("[LanternForager] Serwer gotowy, miejsc na grzyby: %d", #map.spots))
