local M = {}

function M:setup(cfg)
	self.cfg = cfg
end

-- Converts a WSL path to a Windows path.
-- @param wsl_path (string) The WSL path to convert.
-- @param distro (string) The name of the WSL distribution.
-- @return (string) The converted Windows path.
local function to_win_path(wsl_path, distro)
	local win_path
	-- Check if it's a mounted Windows path (e.g., /mnt/c/...)
	if string.sub(wsl_path, 1, 5) == "/mnt/" then
		local drive = string.sub(wsl_path, 6, 6)
		win_path = string.upper(drive) .. ":" .. string.sub(wsl_path, 7)
		win_path = string.gsub(win_path, "/", "\\")
	else
		-- Assume it's a WSL-native path (e.g., /home/user/...)
		win_path = "\\\\wsl.localhost\\" .. distro .. wsl_path
		win_path = string.gsub(win_path, "/", "\\")
	end
	return win_path
end

local get_current = ya.sync(function(_)
	return tostring(cx.active.current.hovered.url)
end)

-- it's necessary to use ya.sync to get sync context vars
-- bacause the plugin is async for default
local get_cfg = ya.sync(function(_)
	return M.cfg
end)

function M.entry()
	local cfg = get_cfg()
	local distro = cfg.wsl_distro or "Arch"
	local quicklook_exe_wsl = cfg.quicklook_path or "/mnt/c/Users/zion/AppData/Local/Programs/QuickLook/QuickLook.exe"
	local file_path_wsl = get_current()

	local file_path_win = "'" .. to_win_path(file_path_wsl, distro) .. "'"

	if cfg.debug then
		ya.dbg("QuickLook Plugin:")
		ya.dbg("==>WSL Path: " .. file_path_wsl)
		ya.dbg("==>Windows Path: " .. file_path_win)
		ya.dbg("==>QuickLook WSL Path: " .. quicklook_exe_wsl)
	end

	os.execute(quicklook_exe_wsl .. " " .. file_path_win .. " -top")
end

return M
