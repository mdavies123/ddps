-- the donage-beerware license (version 69):
--
-- donage-stormrage(us) wrote this code 
-- as long as you retain this notice, you can do whatever you want with this code
-- if we meet someday, and you think this stuff is worth it, you can buy me a beer in return

ddps_locale = {
  ["enUS"] = {
    message_div_enabled         = "divide by 1e3 enabled",
    message_div_disabled        = "divide by 1e3 disabled",
    message_font_bad_conversion = "could not convert %s to a number",
    message_font_changed        = "%s set to %s",
    message_font_dump           = "font config: %s = %s",
    message_font_size_lt0       = "font size must be greater than 0",
    message_font_unknown_field  = "unknown field: %s",
    message_font_usage          = "usage: /ddps font [KEY [VALUE]] -- valid options for KEY are: font || flags || size",
    message_format_changed      = "format set to: %s",
    message_format_current      = "usage: /ddps format [FORMAT] -- format is currently %s",
    message_format_fail         = "could not set format: ",
    message_locale_dump         = "usage: /ddps locale [LOCALE] -- locale is currently %s",
    message_locale_fail         = "%s locale not found",
    message_locale_success      = "locale set to %s",
    message_locked_frame        = "locked frame",
    message_enabled             = "enabled",
    message_disabled            = "disabled",
    message_reset               = "reset",
    message_width_changed       = "sample width set to: %.2f seconds",
    message_width_current       = "usage: /ddps width [NUMBER] -- sample width is currently %.2f seconds",
    message_unlocked_frame      = "unlocked frame",
    message_usage               = "usage: /ddps [%s]"
  }
}
