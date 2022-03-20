

local dt = require 'darktable'
local du = require "lib/dtutils"
local df = require 'lib/dtutils.file'
local dsys = require 'lib/dtutils.system'

du.check_min_api_version("7.0.0", "SetLens")

local script_data = {}
local temp

script_data.destroy = nil -- function to destory the script
script_data.destroy_method = nil -- set to hide for libs since we can't destroy them commpletely yet, otherwise leave as nil
script_data.restart = nil -- how to restart the (lib) script after it's been hidden - i.e. make it visible again

local GUI = { --GUI Elements Table
  lens = {},
  run = {},
}

local mod = 'module_SetLens'
local os_path_seperator = '/'
if dt.configuration.running_os == 'windows' then os_path_seperator = '\\' end


-- Tell gettext where to find the .mo file translating messages for a particular domain
local gettext = dt.gettext
gettext.bindtextdomain('setLens', dt.configuration.config_dir..'\\lua\\locale\\')
dt.print_log( "bindtextdomain: "..dt.configuration.config_dir..'\\lua\\locale\\' )

local function _(msgid)
    dt.print_log( "orig: "..msgid.."  translation: "..gettext.dgettext('setLens', msgid))
    return gettext.dgettext('setLens', msgid)
end

-- declare a local namespace and a couple of variables we'll need to install the module
local mE = {}
mE.event_registered = false  -- keep track of whether we've added an event callback or not
mE.module_installed = false  -- keep track of whether the module is module_installed


local function destroy()
  dt.gui.libs["SetLens_Lib"].visible = false
end

local function restart()
  dt.gui.libs["SetLens_Lib"].visible = true
end

local function install_module()
  if not mE.module_installed then
    dt.register_lib( -- register  module
      'SetLens_Lib', -- Module name
      _('Set Lens Name'), -- name
      true,   -- expandable
      true,   -- resetable
      {[dt.gui.views.lighttable] = {'DT_UI_CONTAINER_PANEL_RIGHT_CENTER', 99}},   -- containers
      dt.new_widget('box'){
        orientation = 'vertical',
        GUI.lens,
        GUI.run
      },

      nil,-- view_enter
      nil -- view_leave
    )
  end
end

local function set_lens()
  images = dt.gui.selection() --get selected images
  if #images < 1 then --ensure enough images selected
    dt.print(_('select at least one image'))
    return
  end

  for i,image in pairs(images) do
    local newlensname = GUI.lens.text
    dt.print_log( 'exif_lens orig: '..image.exif_lens..'  new: '..newlensname  )
    image.exif_lens = newlensname
  end

end

GUI.lens = dt.new_widget('combobox') {
  tooltip = _('Lens name, configure in preferences/lua options'),
}

GUI.run = dt.new_widget('button') {
  label = _('set'),
  tooltip =_('set lens name'),
  clicked_callback = function() set_lens() end
}

local function fillLensList()
  local lenses = dt.preferences.read(mod, "Lenses", "string")
  dt.print_log( "lenses from pref: "..lenses )
  for lens in string.gmatch(lenses, '([^;]+)') do
    GUI.lens[ #GUI.lens + 1] = lens
    dt.print_log ("lens name: " .. lens)
  end
end

local function setCallback( widget )
  dt.print_log("setcallback")
  fillLensList()
end

dt.preferences.register(
    mod, -- script
    "Lenses",	-- name
    "string",	-- type
    _('SetLens: Lens names'),	-- label
    _('semicolon separated list of lens names - restart darktable to take effect'),	-- tooltip
    "",  -- default
    setCallback
)

if dt.gui.current_view().id == "lighttable" then -- make sure we are in lighttable view
  install_module()  -- register the lib
else
  if not mE.event_registered then -- if we are not in lighttable view then register an event to signal when we might be
    -- https://www.darktable.org/lua-api/index.html#darktable_register_event
    dt.register_event(
      "mdouleExample", "view-changed",  -- we want to be informed when the view changes
      function(event, old_view, new_view)
        if new_view.name == "lighttable" and old_view.name == "darkroom" then  -- if the view changes from darkroom to lighttable
          install_module()  -- register the lib
        end
      end
    )
    mE.event_registered = true  --  keep track of whether we have an event handler installed
  end
end

fillLensList()

script_data.destroy = destroy
script_data.restart = restart
script_data.destroy_method = "hide"
script_data.show = restart

return script_data
