local styles = data.raw["gui-style"]["default"]

local function create_banner_texture(mode)
  styles["debugadapter_"..mode.."_banner"] = {
    type = "frame_style",
    padding = 0,
    height = 5,
    graphical_set = {},
    background_graphical_set = {
      base = {
        filename = "__debugadapter__/graphics/"..mode.."-banner.png",
        size = {57, 28},
        overall_tiling_horizontal_size = 29
      }
    }
  }
end

create_banner_texture("debug")
create_banner_texture("profile")