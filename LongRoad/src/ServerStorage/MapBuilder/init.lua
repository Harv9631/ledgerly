--[[
	MapBuilder: bakes the map ONCE in Studio.
	Usage (Studio command bar): require(game.ServerStorage.MapBuilder).Build()
	After baking: set Workspace.StreamingEnabled = true and SAVE THE PLACE FILE.
	Do NOT `rojo build` over a baked place file — that discards the bake.
	Use `rojo serve` + the Studio plugin to sync script changes into the baked file.
]]
local MapBuilder = {}
function MapBuilder.Build()
	require(script.TerrainGen).Build()
	local markerGen = script:FindFirstChild("MarkerGen")
	if markerGen then require(markerGen).Build() end
	local placer = script:FindFirstChild("ModelPlacer")
	if placer then require(placer).Place() end
	print("[MapBuilder] map bake complete — SAVE THE PLACE FILE NOW")
end
return MapBuilder
