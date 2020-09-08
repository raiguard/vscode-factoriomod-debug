local event_log_gui = {}

local gui = require("__flib__.gui")

local constants = require("scripts.constants")
local formatter = require("scripts.formatter")

gui.add_handlers{
  event_log = {
    close_button = {
      on_gui_click = function()
        global.gui.event_log.window.visible = false
      end
    },
    item = {
      on_gui_click = function(e)
        local _, _, index = string.find(e.element.name, "debugadapter_event_log_item__(%d*)")
        local event_data = global.event_log.items[tonumber(index)]
        __DebugAdapter.breakpoint("Inspecting event data")
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
      {type="frame", style="inside_deep_frame", direction="vertical", children={
        -- {type="frame", style="subheader_frame", children={
        --   -- setting margin on switches doesn't work properly...
        --   {type="flow", style_mods={left_margin=8}, children={
        --     {type="switch", left_label_caption="Off", right_label_caption="On", switch_state="right"},
        --   }},
        --   {type="empty-widget", style="flib_horizontal_pusher"}
        -- }},
        {type="scroll-pane",
          style="flib_naked_scroll_pane_no_padding",
          style_mods={width=1000, height=500, left_padding=6, top_padding=2, right_padding=6, bottom_padding=2},
          direction="vertical",
          horizontal_scroll_policy="never",
          save_as="log_scroll_pane"
        }
      }}
    }}
  })
  elems.window.force_auto_center()
  elems.titlebar.flow.drag_target = elems.window

  gui.update_filters("event_log.item", player.index, {"debugadapter_event_log_item"}, "add")

  global.gui.event_log = elems
end

function event_log_gui.toggle()
  global.gui.event_log.window.visible = not global.gui.event_log.window.visible
end

function event_log_gui.log(e)
  if not global.gui.event_log then return end
  local scroll = global.gui.event_log.log_scroll_pane
  local children_count = #scroll.children
  local caption, event_data = formatter(e)
  local next_index = global.event_log.next_index
  local new_line = scroll.add{
    type = "label",
    name = "debugadapter_event_log_item__"..next_index,
    caption = caption
  }
  global.event_log.items[next_index] = event_data
  global.event_log.next_index = next_index + 1
  if children_count == 100 then
    local first = scroll.children[1]
    local _, _, index = string.find(first.name, "debugadapter_event_log_item__(%d*)")
    global.event_log.items[tonumber(index)] = nil
    first.destroy()
  end
  scroll.scroll_to_element(new_line)
end

return event_log_gui