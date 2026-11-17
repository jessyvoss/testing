-- Fish in Space: uploaded art (drawn for this game). Fish sprites are 512x256, facing right.
local A = {}

A.ui = {
	panel = "rbxassetid://119108566860817",
	panel_cyan = "rbxassetid://98160126150619",
	button = "rbxassetid://103797468020500",
	button_cyan = "rbxassetid://77156316591776",
	tile = "rbxassetid://73167866726521",
	tile_cyan = "rbxassetid://117863555761785",
	bracket = "rbxassetid://111850594466740",
	coin = "rbxassetid://135874542876098",
	hook = "rbxassetid://87354694329385",
	glowdot = "rbxassetid://86509944934332",
	petal = "rbxassetid://78322741605144",
	butterfly = "rbxassetid://124737218143430",
	blackhole = "rbxassetid://108258069176156",
}

-- cartoon icons: chunky toon-shaded models with a dark outline, rendered in Blender
-- (LobbyAssets/UI/make_cartoon_icons.py). They are full colour: don't tint them (ImageColor3 stays white).
A.icon = {
	shop = "rbxassetid://84416045308922", -- red shopping basket
	catalog = "rbxassetid://99301147359939", -- blue book
	quests = "rbxassetid://85443763921356", -- clipboard with ticks
	sell = "rbxassetid://112356440011232", -- money bag
	upgrade = "rbxassetid://99707793813421", -- green up arrow
	settings = "rbxassetid://95752731099812", -- cog
	close = "rbxassetid://115627677413760", -- (the close button is drawn as a red button with an X)
	fish = "rbxassetid://120785434334172",
	lock = "rbxassetid://138667405407964",
	star = "rbxassetid://119516926748399",
	auto = "rbxassetid://83110130754792", -- cyan arrows with a play button
	hook = "rbxassetid://134739567969919", -- hook and bobber
	cargo = "rbxassetid://114498371517725", -- bucket
	trophy = "rbxassetid://86232923526884",
	luck = "rbxassetid://122882520128052", -- four-leaf clover
	crown = "rbxassetid://96767406089486",
	gift = "rbxassetid://133449443611981",
	rebirth = "rbxassetid://134945016487421", -- purple circling arrows
	coin = "rbxassetid://135874542876098",
	rod = "rbxassetid://118724409896064", -- fishing rod with reel and bobber
	bait = "rbxassetid://118197782392178", -- can of worms
	throw = "rbxassetid://121061257097775", -- bobber flying along a dotted arc
}

A.fish = {
	space_guppy = "rbxassetid://83170352023467",
	moon_minnow = "rbxassetid://124879163843365",
	star_shrimp = "rbxassetid://118311658327092",
	dust_puffling = "rbxassetid://134435173440345",
	cosmo_carp = "rbxassetid://99126169480794",
	twinkle_tetra = "rbxassetid://123649808938397",
	comet_krill = "rbxassetid://87373069856535",
	orbit_sardine = "rbxassetid://133957417969051",
	pebble_crab = "rbxassetid://119690722778253",
	lunar_loach = "rbxassetid://121531486653051",
	comet_tail = "rbxassetid://102903137747142",
	nebula_jelly = "rbxassetid://115123642337457",
	orbit_eel = "rbxassetid://139765687989468",
	plasma_perch = "rbxassetid://71199672441241",
	aurora_angelfish = "rbxassetid://100830854041216",
	rocket_trout = "rbxassetid://109445059992116",
	saturn_snapper = "rbxassetid://80982853785945",
	nova_clownfish = "rbxassetid://79881157547257",
	halo_seahorse = "rbxassetid://77383888767254",
	crystal_spiker = "rbxassetid://85739763750012",
	meteor_stinger = "rbxassetid://92898996155736",
	rockjaw = "rbxassetid://134662902581529",
	quasar_lionfish = "rbxassetid://128842737708126",
	ion_barracuda = "rbxassetid://122534191267525",
	gem_shell_snapper = "rbxassetid://129438499264012",
	gravity_eater = "rbxassetid://123437498756202",
	void_fang = "rbxassetid://111262837566580",
	pulsar_reaper = "rbxassetid://132179077739723",
	eclipse_leviathan = "rbxassetid://110043511623801",
	event_horizon_eel = "rbxassetid://96055373500915",
	lost_satellite = "rbxassetid://83801693026805",
	astronaut_boot = "rbxassetid://122355863953608",
	cosmic_rubber_duck = "rbxassetid://138857738968893",
	space_soda_can = "rbxassetid://127228310753941",
}

-- holiday fish and the secret fish use the picture of the fish they're based on (Config.SPECIAL_FISH)
do
	local Config = require(script.Parent:WaitForChild("Config"))
	for _, f in Config.SPECIAL_FISH do
		A.fish[f.id] = A.fish[f.id] or A.fish[f.base]
	end
end

return A
