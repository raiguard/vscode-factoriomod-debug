local event_log_gui = {}

local gui = require("__flib__.gui")

gui.add_handlers{
  event_log = {
    close_button = {
      on_gui_click = function()
        global.gui.event_log.window.visible = false
      end
    }
  }
}

function event_log_gui.create(player)
  local elems = gui.build(player.gui.screen, {
    {type="frame", direction="vertical", elem_mods={visible=false}, save_as="window", children={
      {type="flow", save_as="titlebar.flow", children={
        {type="label", style="frame_title", caption="Event log", elem_mods={ignored_by_interaction=true}},
        {type="empty-widget", style="flib_titlebar_drag_handle", elem_mods={ignored_by_interaction=true}},
        {type="sprite-button",
          style="frame_action_button",
          sprite="utility/close_white",
          hovered_sprite="utility/close_black",
          clicked_sprite="utility/close_black",
          handlers="event_log.close_button",
          save_as="titlebar.close_button"
        }
      }},
      {type="frame", style="inside_shallow_frame", style_mods={width=300, height=300}}
    }}
  })
  elems.window.force_auto_center()
  elems.titlebar.flow.drag_target = elems.window

  global.gui.event_log = elems
end

function event_log_gui.toggle()
  global.gui.event_log.window.visible = not global.gui.event_log.window.visible
end

return event_log_gui