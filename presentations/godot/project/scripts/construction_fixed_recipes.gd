extends RefCounted
# Native DF53.16 fixed recipes: material_candidates.json workshop_reference,
# utility_reference, matching special/shortage captures and history transitions.
# Labels are verbatim native copy; history_class is internal selection metadata.
const RECIPES = {
 "Workshop:Carpenters": {
  "placement": "Click a tile to place the Carpenter's Workshop.",
  "heading": "Select materials for the Carpenter's Workshop.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Masons": {
  "placement": "Click a tile to place the Stoneworker's Workshop.",
  "heading": "Select materials for the Stoneworker's Workshop.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Craftsdwarfs": {
  "placement": "Click a tile to place the Craftsdwarf's Workshop.",
  "heading": "Select materials for the Craftsdwarf's Workshop.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Mechanics": {
  "placement": "Click a tile to place the Mechanic's Workshop.",
  "heading": "Select materials for the Mechanic's Workshop.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Bowyers": {
  "placement": "Click a tile to place the Bowyer's Workshop.",
  "heading": "Select materials for the Bowyer's Workshop.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Jewelers": {
  "placement": "Click a tile to place the Jeweler's Workshop.",
  "heading": "Select materials for the Jeweler's Workshop.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Siege": {
  "placement": "Click a tile to place the Siege Workshop.",
  "heading": "Select materials for the Siege Workshop.",
  "last": true,
  "needs": [
   [
    "3 building material non-economic items",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Ashery": {
  "placement": "Click a tile to place the Ashery.",
  "heading": "Select materials for the Ashery.",
  "last": false,
  "needs": [
   [
    "blocks",
    " - make at a workshop first"
   ],
   [
    "empty barrel",
    " - make at a workshop first"
   ],
   [
    "lye/milk-free bucket",
    " - make at a workshop first"
   ]
  ],
  "history_class": ""
 },
 "Workshop:MetalsmithsForge": {
  "placement": "Click a tile to place the Metalsmith's Forge.",
  "heading": "Select materials for the Metalsmith's Forge.",
  "last": false,
  "needs": [
   [
    "fire-safe anvil",
    " - make at a workshop first"
   ],
   [
    "fire-safe building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": ""
 },
 "Workshop:Leatherworks": {
  "placement": "Click a tile to place the Leather Works.",
  "heading": "Select materials for the Leather Works.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Loom": {
  "placement": "Click a tile to place the Loom.",
  "heading": "Select materials for the Loom.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Clothiers": {
  "placement": "Click a tile to place the Clothier's Shop.",
  "heading": "Select materials for the Clothier's Shop.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Dyers": {
  "placement": "Click a tile to place the Dyer's Shop.",
  "heading": "Select materials for the Dyer's Shop.",
  "last": false,
  "needs": [
   [
    "empty barrel",
    " - make at a workshop first"
   ],
   [
    "lye/milk-free bucket",
    " - make at a workshop first"
   ]
  ],
  "history_class": ""
 },
 "Workshop:Butchers": {
  "placement": "Click a tile to place the Butcher's Shop.",
  "heading": "Select materials for the Butcher's Shop.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Tanners": {
  "placement": "Click a tile to place the Tanner's Shop.",
  "heading": "Select materials for the Tanner's Shop.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Fishery": {
  "placement": "Click a tile to place the Fishery.",
  "heading": "Select materials for the Fishery.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Kitchen": {
  "placement": "Click a tile to place the Kitchen.",
  "heading": "Select materials for the Kitchen.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Farmers": {
  "placement": "Click a tile to place the Farmer's Workshop.",
  "heading": "Select materials for the Farmer's Workshop.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Still": {
  "placement": "Click a tile to place the Still.",
  "heading": "Select materials for the Still.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Workshop:Kennels": {
  "placement": "Click a tile to place the Vermin Catcher's Shop.",
  "heading": "Select materials for the Vermin Catcher's Shop.",
  "last": true,
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "building material"
 },
 "Furnace:WoodFurnace": {
  "placement": "Click a tile to place the Wood Furnace.",
  "heading": "Select materials for the Wood Furnace.",
  "last": true,
  "needs": [
   [
    "fire-safe building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "fire-safe building material"
 },
 "Furnace:Smelter": {
  "placement": "Click a tile to place the Smelter.",
  "heading": "Select materials for the Smelter.",
  "last": true,
  "needs": [
   [
    "fire-safe building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "fire-safe building material"
 },
 "Furnace:GlassFurnace": {
  "placement": "Click a tile to place the Glass Furnace.",
  "heading": "Select materials for the Glass Furnace.",
  "last": true,
  "needs": [
   [
    "fire-safe building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "fire-safe building material"
 },
 "Furnace:Kiln": {
  "placement": "Click a tile to place the Kiln.",
  "heading": "Select materials for the Kiln.",
  "last": true,
  "needs": [
   [
    "fire-safe building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "history_class": "fire-safe building material"
 },
 "Support": {
  "placement": "Click a tile to place the Support.",
  "heading": "Select materials for the Support.",
  "last": true,
  "history_class": "building material",
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ]
 },
 "ArcheryTarget": {
  "placement": "Click a tile to place the Archery Target.",
  "heading": "Select materials for the Archery Target.",
  "last": true,
  "history_class": "building material",
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ]
 },
 "BarsVertical": {
  "placement": "Click a tile to place the Vertical Bars.",
  "heading": "Select materials for the Vertical Bars.",
  "last": true,
  "history_class": "bars",
  "needs": [
   [
    "building material bars",
    " - make at a workshop first"
   ]
  ]
 },
 "BarsFloor": {
  "placement": "Click a tile to place the Floor Bars.",
  "heading": "Select materials for the Floor Bars.",
  "last": true,
  "history_class": "bars",
  "needs": [
   [
    "building material bars",
    " - make at a workshop first"
   ]
  ]
 },
 "WindowGem": {
  "placement": "Click a tile to place the Gem Window.",
  "heading": "Select materials for the Gem Window.",
  "last": true,
  "history_class": "cut gems",
  "needs": [
   [
    "3 cut gems",
    " - make at a workshop first"
   ]
  ]
 },
 "TradeDepot": {
  "placement": "Click a tile to place the Trade Depot.",
  "heading": "Select materials for the Trade Depot.",
  "last": true,
  "history_class": "building material",
  "needs": [
   [
    "3 building material non-economic items",
    " - mine rock or chop trees"
   ]
  ]
 },
 "Trap:Lever": {
  "placement": "Click a tile to place the Lever.",
  "heading": "Select materials for the Lever.",
  "last": true,
  "history_class": "mechanisms",
  "needs": [
   [
    "mechanisms",
    " - make at a workshop first"
   ]
  ]
 },
 "Trap:StoneFallTrap": {
  "placement": "Click a tile to place the Stone-Fall Trap.",
  "heading": "Select materials for the Stone-Fall Trap.",
  "last": true,
  "history_class": "mechanisms",
  "needs": [
   [
    "mechanisms",
    " - make at a workshop first"
   ]
  ]
 },
 "Trap:CageTrap": {
  "placement": "Click a tile to place the Cage Trap.",
  "heading": "Select materials for the Cage Trap.",
  "last": true,
  "history_class": "mechanisms",
  "needs": [
   [
    "mechanisms",
    " - make at a workshop first"
   ]
  ]
 },
 "GearAssembly": {
  "placement": "Click a tile to place the Gear Assembly.",
  "heading": "Select materials for the Gear Assembly.",
  "last": true,
  "history_class": "mechanisms",
  "needs": [
   [
    "mechanisms",
    " - make at a workshop first"
   ]
  ]
 },
 "AxleVertical": {
  "placement": "Click a tile to place the Vertical Axle.",
  "heading": "Select materials for the Vertical Axle.",
  "last": true,
  "history_class": "logs",
  "needs": [
   [
    "logs",
    " - chop down trees"
   ]
  ]
 },
 "Workshop:Millstone": {
  "placement": "Click a tile to place the Millstone.",
  "heading": "Select materials for the Millstone.",
  "last": false,
  "history_class": "",
  "needs": [
   [
    "millstone",
    " - make at a workshop first"
   ],
   [
    "mechanisms",
    " - make at a workshop first"
   ]
  ]
 },
 "Trap:TrackStop": {
  "placement": "Click a tile to place the Track Stop.                                   Set the friction and auto-dump direction.",
  "heading": "Select materials for the Track Stop.",
  "last": true,
  "history_class": "building material",
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ]
 },
 "Well": {
  "placement": "Click a tile to place the Well.",
  "heading": "Select materials for the Well.",
  "last": false,
  "history_class": "",
  "needs": [
   [
    "blocks",
    " - make at a workshop first"
   ],
   [
    "lye/milk-free bucket",
    " - make at a workshop first"
   ],
   [
    "chain",
    " - make at a workshop first"
   ],
   [
    "mechanisms",
    " - make at a workshop first"
   ]
  ]
 },
 "ScrewPump": {
  "placement": "Click a tile to place the Screw Pump.",
  "heading": "Select materials for the Screw Pump.",
  "last": false,
  "history_class": "",
  "needs": [
   [
    "blocks",
    " - make at a workshop first"
   ],
   [
    "screw trap component",
    " - make at a workshop first"
   ],
   [
    "pipe section",
    " - make at a workshop first"
   ]
  ]
 },
 "WaterWheel": {
  "placement": "Click a tile to place the Water Wheel.",
  "heading": "Select materials for the Water Wheel.",
  "last": true,
  "history_class": "logs",
  "needs": [
   [
    "3 logs",
    " - chop down trees"
   ]
  ]
 },
 "Windmill": {
  "placement": "Click a tile to place the Windmill.",
  "heading": "Select materials for the Windmill.",
  "last": true,
  "history_class": "logs",
  "needs": [
   [
    "4 logs",
    " - chop down trees"
   ]
  ]
 },
 "SiegeEngine:Ballista": {
  "placement": "Click a tile to place the Ballista.",
  "heading": "Select materials for the Ballista.",
  "last": true,
  "history_class": "ballista parts",
  "needs": [
   [
    "3 ballista parts",
    " - make at a workshop first"
   ]
  ]
 },
 "SiegeEngine:Catapult": {
  "placement": "Click a tile to place the Catapult.",
  "heading": "Select materials for the Catapult.",
  "last": true,
  "history_class": "catapult parts",
  "needs": [
   [
    "3 catapult parts",
    " - make at a workshop first"
   ]
  ]
 },
 "SiegeEngine:BoltThrower": {
  "placement": "Click a tile to place the Bolt Thrower.",
  "heading": "Select materials for the Bolt Thrower.",
  "last": false,
  "history_class": "",
  "needs": [
   [
    "bolt thrower parts",
    " - make at a workshop first"
   ],
   [
    "mechanisms",
    " - make at a workshop first"
   ],
   [
    "chain",
    " - make at a workshop first"
   ],
   [
    "empty bin",
    " - make at a workshop first"
   ]
  ]
 },
 "Workshop:Custom:SCREW_PRESS": {
  "placement": "Click a tile to place the Screw Press.",
  "heading": "Select materials for the Screw Press.",
  "last": true,
  "history_class": "mechanisms",
  "needs": [
   [
    "2 mechanisms",
    " - make at a workshop first"
   ]
  ]
 },
 "Workshop:Custom:SOAP_MAKER": {
  "placement": "Click a tile to place the Soap Maker's Workshop.",
  "heading": "Select materials for the Soap Maker's Workshop.",
  "last": false,
  "history_class": "",
  "needs": [
   [
    "empty bucket",
    " - make at a workshop first"
   ],
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ]
 },
 "Workshop:MagmaForge": {
  "placement": "Click a tile to place the Magma Forge.",
  "heading": "Select materials for the Magma Forge.",
  "last": false,
  "history_class": "",
  "needs": [
   [
    "magma-safe anvil",
    " - make at a workshop first"
   ],
   [
    "magma-safe building material non-economic item",
    " - mine rock or chop trees"
   ]
  ]
 },
 "Furnace:MagmaSmelter": {
  "placement": "Click a tile to place the Magma Smelter.",
  "heading": "Select materials for the Magma Smelter.",
  "last": true,
  "history_class": "magma-safe building material",
  "needs": [
   [
    "magma-safe building material non-economic item",
    " - mine rock or chop trees"
   ]
  ]
 },
 "Furnace:MagmaGlassFurnace": {
  "placement": "Click a tile to place the Magma Glass Furnace.",
  "heading": "Select materials for the Magma Glass Furnace.",
  "last": true,
  "history_class": "magma-safe building material",
  "needs": [
   [
    "magma-safe building material non-economic item",
    " - mine rock or chop trees"
   ]
  ]
 },
 "Furnace:MagmaKiln": {
  "placement": "Click a tile to place the Magma Kiln.",
  "heading": "Select materials for the Magma Kiln.",
  "last": true,
  "history_class": "magma-safe building material",
  "needs": [
   [
    "magma-safe building material non-economic item",
    " - mine rock or chop trees"
   ]
  ]
 },
 "RoadPaved": {
  "placement": "Click a tile to be a corner of the Paved Road.",
  "heading": "Select materials for the Paved Road.",
  "last": true,
  "history_class": "building material",
  "needs": [
   [
    "building material non-economic item",
    " - mine rock or chop trees"
   ]
  ],
  "access_plural": [
   "building material non-economic items"
  ],
  "needs_only_if_empty": true
 },
 "AxleHorizontal": {
  "placement": "Click a tile to be one end of the Horizontal Axle.",
  "heading": "Select materials for the Horizontal Axle.",
  "last": true,
  "history_class": "logs",
  "needs": [
   [
    "logs",
    " - chop down trees"
   ]
  ],
  "access_plural": [
   "logs"
  ],
  "needs_only_if_empty": true
 },
 "Rollers": {
  "placement": "Click a tile to be one end of the Rollers.",
  "heading": "Select materials for the Rollers.",
  "last": false,
  "history_class": "",
  "needs": [
   [
    "mechanisms",
    " - make at a workshop first"
   ],
   [
    "chain",
    " - make at a workshop first"
   ]
  ],
  "access_plural": [
   "mechanisms",
   "chains"
  ],
  "needs_only_if_empty": true
 },
 "Weapon": {
  "placement": "Click a tile to place the Upright Spear/Spike.",
  "heading": "Select materials for the Upright Spear/Spike.",
  "last": true,
  "history_class": "upright weapons",
  "needs": [
   [
    "item",
    ""
   ]
  ]
 },
 "Trap:WeaponTrap": {
  "placement": "Click a tile to place the Weapon Trap.",
  "heading": "Select materials for the Weapon Trap.",
  "last": false,
  "history_class": "",
  "needs": [
   [
    "mechanisms",
    " - make at a workshop first"
   ],
   [
    "item",
    ""
   ]
  ]
 },
 "Construction:ReinforcedWall": {
  "placement": "Click a tile to be a corner of the Reinforced Wall.",
  "heading": "Select materials for the Reinforced Wall.",
  "last": false,
  "history_class": "",
  "omit_needs": true,
  "needs": [
   [
    "building material non-economic item",
    ""
   ],
   [
    "metal bars",
    ""
   ]
  ],
  "access_plural": [
   "building material non-economic items",
   "metal bars"
  ]
 }
}
