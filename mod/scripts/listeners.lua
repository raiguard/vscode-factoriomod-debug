-- the debugger is only usable in singleplayer, so the code assumes that only one player is connected

local event = require("__flib__.event")
local gui = require("__flib__.gui")

local global_data = require("scripts.global-data")

local banner_gui = require("scripts.gui.banner")

-- BOOTSTRAP

local function on_init()
  gui.init()
  gui.build_lookup_tables()

  global_data.init()
end

local function on_load()
  gui.build_lookup_tables()
end

event.on_configuration_changed(function(e)
  gui.init()

  -- destroy all GUIs
  for _, tbl in pairs(global.gui) do
    tbl.parent.destroy()
  end

  -- reset global
  global_data.init()
end)

-- DISPLAY

event.register({defines.events.on_player_display_resolution_changed, defines.events.on_player_display_scale_changed}, function(e)
  banner_gui.set_width(game.get_player(e.player_index))
end)

-- TICK

local function on_tick(e)
  -- on_configuration_changed contains the previous state of players, so wait to create GUIs until the first tick
  if global.flags.create_guis then
    global.flags.create_guis = false

    -- find connected player
    local player
    for _, p in pairs(game.players) do
      if p.connected then player = p end
    end
    if not player then error("could not find connected player") end

    -- create GUIs
    banner_gui.create(player)
  end
end

-- return shared events
return {
  on_init = on_init,
  on_load = on_load,
  on_tick = on_tick
}