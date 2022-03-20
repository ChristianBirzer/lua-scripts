--[[
    This file is part of darktable,
    copyright (c) 2022 Christian Birzer
    darktable is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
    darktable is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
    You should have received a copy of the GNU General Public License
    along with darktable.  If not, see <http://www.gnu.org/licenses/>.
]]

local dt = require 'darktable'
local du = require "lib/dtutils"
local df = require 'lib/dtutils.file'
local dsys = require 'lib/dtutils.system'

du.check_min_api_version("7.0.0", "MetadataTool")

local script_data = {}
local temp

script_data.destroy = nil -- function to destory the script
script_data.destroy_method = nil -- set to hide for libs since we can't destroy them commpletely yet, otherwise leave as nil
script_data.restart = nil -- how to restart the (lib) script after it's been hidden - i.e. make it visible again

local metadataTool = {
  substitutes = {},
  placeholders = {"ROLL_NAME","FILE_FOLDER","FILE_NAME","FILE_EXTENSION","ID","VERSION","SEQUENCE",
                  "EXIF_YEAR","EXIF_MONTH","EXIF_DAY","EXIF_HOUR","EXIF_MINUTE","EXIF_SECOND",
                  "STARS","LABELS","MAKER","MODEL","TITLE","CREATOR","PUBLISHER","RIGHTS",
                  "EXIF_ISO","EXIF_EXPOSURE","EXIF_EXPOSURE_BIAS","EXIF_APERTURE","EXIF_FOCUS_DISTANCE",
                  "EXIF_FOCAL_LENGTH","LONGITUDE","LATITUDE","ELEVATION","LENS","DESCRIPTION","EXIF_CROP"},
}

local GUI = { --GUI Elements Table
  target = {},
  pattern = {},
  run = {},
}

local mod = 'module_MetadataTool'
local os_path_seperator = '/'
if dt.configuration.running_os == 'windows' then os_path_seperator = '\\' end


-- Tell gettext where to find the .mo file translating messages for a particular domain
local gettext = dt.gettext
gettext.bindtextdomain('metadataTool', dt.configuration.config_dir..'\\lua\\locale\\')
dt.print_log( "bindtextdomain: "..dt.configuration.config_dir..'\\lua\\locale\\' )

local function _(msgid)
    dt.print_log( "orig: "..msgid.."  translation: "..gettext.dgettext('metadataTool', msgid))
    return gettext.dgettext('metadataTool', msgid)
end

-- declare a local namespace and a couple of variables we'll need to install the module
local mE = {}
mE.event_registered = false  -- keep track of whether we've added an event callback or not
mE.module_installed = false  -- keep track of whether the module is module_installed


local function destroy()
  dt.gui.libs["metadataTool_Lib"].visible = false
end

local function restart()
  dt.gui.libs["metadataTool_Lib"].visible = true
end

local function install_module()
  if not mE.module_installed then
    dt.register_lib( -- register  module
      'metadataTool_Lib', -- Module name
      _('Metadata Tool'), -- name
      true,   -- expandable
      true,   -- resetable
      {[dt.gui.views.lighttable] = {'DT_UI_CONTAINER_PANEL_RIGHT_CENTER', 99}},   -- containers
      dt.new_widget('box'){
        orientation = 'vertical',
        GUI.target,
        GUI.pattern,
        GUI.run
      },

      nil,-- view_enter
      nil -- view_leave
    )
  end
end


local function build_substitution_list(image, sequence)
  -- build the argument substitution list from each image
  -- local datetime = os.date("*t")
  local colorlabels = {}
  if image.red then table.insert(colorlabels, "red") end
  if image.yellow then table.insert(colorlabels, "yellow") end
  if image.green then table.insert(colorlabels, "green") end
  if image.blue then table.insert(colorlabels, "blue") end
  if image.purple then table.insert(colorlabels, "purple") end
  local labels = #colorlabels == 1 and colorlabels[1] or du.join(colorlabels, ",")
  local eyear,emon,eday,ehour,emin,esec = string.match(image.exif_datetime_taken, "(%d-):(%d-):(%d-) (%d-):(%d-):(%d-)$")
  local replacements = {image.film,
                        image.path,
                        df.get_filename(image.filename),
                        string.upper(df.get_filetype(image.filename)),
                        image.id,image.duplicate_index,
                        string.format("%04d", sequence),
                        eyear,
                        emon,
                        eday,
                        ehour,
                        emin,
                        esec,
                        image.rating,
                        labels,
                        image.exif_maker,
                        image.exif_model,
                        image.title,
                        image.creator,
                        image.publisher,
                        image.rights,
                        string.format("%d", image.exif_iso),
                        string.format("1/%.0f", 1/image.exif_exposure),
                        image.exif_exposure_bias,
                        string.format("%.1f", image.exif_aperture),
                        image.exif_focus_distance,
                        image.exif_focal_length,
                        image.longitude,
                        image.latitude,
                        image.elevation,
                        image.exif_lens,
                        image.description,
                        image.exif_crop
                      }

  for i=1,#metadataTool.placeholders,1 do metadataTool.substitutes[metadataTool.placeholders[i]] = replacements[i] end
end

local function substitute_list(str)
  -- replace the substitution variables in a string
  for match in string.gmatch(str, "%$%(.-%)") do
    local var = string.match(match, "%$%((.-)%)")
    if metadataTool.substitutes[var] then
      str = string.gsub(str, "%$%("..var.."%)", metadataTool.substitutes[var])
    else
      dt.print_error(_("unrecognized variable " .. var))
      dt.print(_("unknown variable " .. var .. ", aborting..."))
      return -1
    end
  end
  return str
end

local function clear_substitute_list()
  for i=1,#metadataTool.placeholders,1 do metadataTool.substitutes[metadataTool.placeholders[i]] = nil end
end

local function writeMetadata()

  local pattern = GUI.pattern.text
  dt.preferences.write(mod, "Template", "string", pattern)

  images = dt.gui.selection() --get selected images
  if #images < 1 then --ensure enough images selected
    dt.print(_('select at least one image'))
    return
  end

  for i,image in pairs(images) do

    if string.len(pattern) > 0 then
      build_substitution_list(image, i)

      local metadata_str = substitute_list(pattern)
      dt.print_log( 'pattern='..pattern )
      dt.print_log( 'metadata_str='..metadata_str )

      if metadata_str == -1 then
        dt.print(_("unable to do variable substitution, exiting..."))
        return
      end
      clear_substitute_list()

      image.notes = metadata_str

--    local newlensname = GUI.lens.text
--    dt.print_log( 'exif_lens orig: '..image.exif_lens..'  new: '..newlensname  )
--    image.exif_lens = newlensname
    end
  end
end

GUI.target = dt.new_widget('combobox') {
  tooltip = _('Target metadata field'),
}

GUI.pattern = dt.new_widget('entry') {
  tooltip = _('Metadata pattern'),
  placeholder = _('Enter the metadata replacement pattern'),
  editable = true
}

GUI.run = dt.new_widget('button') {
  label = _('Write metadata'),
  tooltip =_('Write metadata'),
  clicked_callback = function() writeMetadata() end
}

local function readTemplates()
  local template = dt.preferences.read(mod, "Template", "string")
  GUI.pattern.text = template
end

local function setCallback( widget )
  dt.print_log("setcallback")
  fillLensList()
end

dt.preferences.register(
    mod, -- script
    "Templates",	-- name
    "string",	-- type
    _('Metadata Tool: Templates'),	-- label
    _('semicolon separated list of templates'),	-- tooltip
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

readTemplates()

script_data.destroy = destroy
script_data.restart = restart
script_data.destroy_method = "hide"
script_data.show = restart

return script_data
