local banner_gui = {}

local gui = require("__flib__.gui")

function banner_gui.create(player)
  local mode = __DebugAdapter and "debug" or "profile"
  local label = __DebugAdapter and "DEBUGGING" or "PROFILING"
  local color = __DebugAdapter and {255, 50, 50} or {50, 255, 255}
  local elems = gui.build(player.gui.screen, {
    {type="flow",
      style_mods={width=player.display_resolution.width / player.display_scale, horizontal_align="center"},
      direction="vertical",
      elem_mods={ignored_by_interaction=true},
      save_as="flow",
      children={
        {type="frame", style="debugadapter_"..mode.."_banner", style_mods={horizontally_stretchable=true}, elem_mods={ignored_by_interaction=true}},
        {type="label", style_mods={font="default-game", font_color=color}, caption=label, elem_mods={ignored_by_interaction=true}}
      }
    }
  })
  global.gui.banner = elems.flow
end

function banner_gui.destroy()
  global.gui.banner.destroy()
end

return banner_gui