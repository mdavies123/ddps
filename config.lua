local function get_default_config()
  return {
    div_by_1e3 = true,
    enabled = true,
    format_base = "(%.2fk)",
    draggable = false,
    flags = "outline",
    font = "Font/FrizQT__.ttf",
    point = {
      [1] = "center",
      [2] = nil,
      [3] = 0,
      [4] = 0
    },
    size = 10,
    pool_size = 8192,
    width = 5.0
  }
end