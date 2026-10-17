--!nonstrict
-- PORT ADDITIONS (not from the 2D game): village services for the grind loop.
-- Positions are compact-area px, like Adventure.FEATURES: { key, name, x, y, kind }.
-- Kinds: shop (weapons/armour for runes), inn (heal + respawn point), waystone (travel).
return {
	FEATURES = {
		home = {
			{ "shop", "Oakvale Outfitter", 600, 390, "shop" },
			{ "inn", "Oakvale Inn · bed", 230, 300, "inn" },
			{ "waystone_home", "Oakvale waystone", 480, 210, "waystone" },
		},
		dunmere = {
			{ "shop", "Dunmere Outfitter", 330, 395, "shop" },
			{ "inn", "Dunmere Inn · bed", 230, 270, "inn" },
			{ "waystone_dunmere", "Dunmere waystone", 480, 210, "waystone" },
		},
	},
}
