-- the donage-beerware license (version 69):
--
-- donage-stormrage(us) wrote this code 
-- as long as you retain this notice, you can do whatever you want with this code
-- if we meet someday, and you think this stuff is worth it, you can buy me a beer in return

ddps_locale = {}

ddps_locale["enUS"] = {
  message_font_bad_conversion = "could not convert %s to a number",
  message_font_changed        = "%s set to %s",
  message_font_dump           = "font config: %s = %s",
  message_font_size_lt0       = "font size must be greater than 0",
  message_font_unknown_field  = "unknown field: %s",
  message_font_usage          = "usage: /ddps font <field name> [<string||number>] -- values for <field name> are: font, flags, size",
  message_format_changed      = "format set to: %s",
  message_format_current      = "usage: /ddps format <string> -- format is currently %s",
  message_format_fail         = "could not set format: ",
  message_locale_dump         = "usage: /ddps locale <string> -- locale is currently %s",
  message_locale_fail         = "%s locale not found",
  message_locale_success      = "locale set to %s",
  message_locked_frame        = "locked frame",
  message_enabled             = "enabled",
  message_disabled            = "disabled",
  message_width_changed       = "sample width set to: %.2f seconds",
  message_width_current       = "usage: /ddps width <number> -- sample width is currently %.2f seconds",
  message_unlocked_frame      = "unlocked frame",
  message_usage               = "usage: /ddps (%s)"
}
