local event = require("__flib__.event")
local reverse_defines = require("__flib__.reverse-defines")

-- BOOTSTRAP

local function on_init()
  local breakpoint
end

local function on_load()

end

event.on_configuration_changed(function(e)

end)

local id = event.generate_id()

local function print_event(e)
  local name = reverse_defines.events[e.name] or e.input_name or "custom mod event"
  local tick = e.tick
  e.name = nil
  e.tick = nil
  e.input_name = nil
  e.__debug = nil
  game.print(tick..": [color=255,255,100]<"..name..">[/color] "..serpent.line(e))
end

local function detect_events()
  local i = 1
  while true do
    local status = pcall(script.on_event, i, print_event)
    if not status then break end
    i = i + 1
  end
end
detect_events()

event.register("rb-toggle-gui", function()
  event.raise(id, {message="foo"})
  detect_events()
end)

event.on_nth_tick(600, detect_events)

-- return shared events
return {
  on_init = on_init,
  on_load = on_load
}