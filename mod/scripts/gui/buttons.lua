local buttons_gui = {}

local gui = require("__flib__.gui")
local mod_gui = require("mod-gui")

local event_log_gui = require("scripts.gui.event-log")

gui.add_handlers{
  mod_gui = {
    event_log_button = {
      on_gui_click = function()
        event_log_gui.toggle()
      end
    }
  }
}

function buttons_gui.create(player)
  local elems = gui.build(mod_gui.get_button_flow(player), {
    -- debugging buttons
    {type="condition", condition=__DebugAdapter, children={
      {type="button", style=mod_gui.button_style, caption="Event log", handlers="mod_gui.event_log_button"}
    }},
    -- profiling buttons
    {type="condition", condition=__Profiler, children={}}
  })
end

return buttons_gui