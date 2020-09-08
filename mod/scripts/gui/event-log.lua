local event_log_gui = {}

local gui = require("__flib__.gui")

local constants = require("scripts.constants")

local function rich_text(key, value, inner)
  if key == "color" then
    value = constants.colors[value]
  elseif key == "font" then
    value = constants.fonts[value]
  end
  return "["..key.."="..value.."]"..inner.."[/"..key.."]"
end

gui.add_handlers{
  event_log = {
    close_button = {
      on_gui_click = function()
        global.gui.event_log.window.visible = false
      end
    }
  }
}

local function generate_dummy_text()
  local children = {}
  for i = 1, 50 do
    children[i] = {type="label",
    caption=rich_text("font", "tick", rich_text("color", "tick", "0."))
    .." "
    ..rich_text("color", "event_name", "on_player_created ")
    ..rich_text("font", "tick", rich_text("color", "tick", i.."  "))
    .."{player_index=1}"
  }
  end
  return children
end

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
      {type="frame", style="inside_deep_frame", direction="vertical", children={
        {type="frame", style="subheader_frame", children={
          -- setting margin on switches doesn't work properly...
          {type="flow", style_mods={left_margin=8}, children={
            {type="switch", left_label_caption="Off", right_label_caption="On"},
          }},
          {type="empty-widget", style="flib_horizontal_pusher"}
        }},
        {type="scroll-pane",
          style="flib_naked_scroll_pane_no_padding",
          style_mods={width=700, height=500, left_padding=6, top_padding=2, right_padding=6, bottom_padding=2},
          direction="vertical",
          children=generate_dummy_text()
        }
      }}
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