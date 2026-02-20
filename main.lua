local M = {}

function M:setup(cfg)
	self.cfg = cfg
end

---
-- 解析路径为最终的、真实的绝对路径。
local function to_abs_path(path_str)
	local safe_path = string.format("%q", path_str)
	local command = "readlink -f " .. safe_path

	local f = io.popen(command)
	if not f then
		return nil, "Failed to execute 'readlink' command."
	end

	local real_path = f:read("*a")
	local success, _, exit_code = f:close()

	if not success or exit_code ~= 0 or real_path == "" then
		return nil, "Failed to resolve path: " .. path_str
	end

	return real_path:gsub("[\r\n]$", "")
end

-- Converts a WSL path to a Windows path.
local function to_win_path(wsl_path, distro)
	local win_path
	if string.sub(wsl_path, 1, 5) == "/mnt/" then
		local drive = string.sub(wsl_path, 6, 6)
		win_path = string.upper(drive) .. ":" .. string.sub(wsl_path, 7)
		win_path = string.gsub(win_path, "/", "\\")
	else
		win_path = "\\\\wsl.localhost\\" .. distro .. wsl_path
		win_path = string.gsub(win_path, "/", "\\")
	end
	return win_path
end

local get_current_abs_path = ya.sync(function()
	local current_file = cx.active.current.hovered
	if current_file.cha.is_link then
		return to_abs_path(tostring(current_file.link_to))
	else
		return to_abs_path(tostring(current_file.url))
	end
end)

local get_cfg = ya.sync(function(_)
	return M.cfg
end)

function M.entry()
	local cfg = get_cfg()
	local distro = cfg.wsl_distro or "Arch"
	local quicklook_exe_wsl = cfg.quicklook_path or "/mnt/c/Users/zion/AppData/Local/Programs/QuickLook/QuickLook.exe"
	local file_path_wsl = get_current_abs_path()

	-- 恢复使用单引号包裹，因为我们继续使用 os.execute (底层是 /bin/sh)
	local file_path_win = "'" .. to_win_path(file_path_wsl, distro) .. "'"

	if cfg.debug then
		ya.dbg("QuickLook Plugin:")
		ya.dbg("==>WSL Path: " .. file_path_wsl)
		ya.dbg("==>Windows Path: " .. file_path_win)
		ya.dbg("==>QuickLook WSL Path: " .. quicklook_exe_wsl)
	end

	-- 1. 将脚本固定写入 Linux 的 /tmp 目录，每次直接覆盖，不产生垃圾
	local tmp_ps_wsl_path = "/tmp/yazi_quicklook_activate.ps1"
	local f = io.open(tmp_ps_wsl_path, "w")
	if f then
		f:write([[
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
}
"@
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.ElapsedMilliseconds -lt 3000) {
    $found = $false
    [Win32]::EnumWindows({
        param($hWnd, $lParam)
        $sb = New-Object System.Text.StringBuilder 256
        [Win32]::GetWindowText($hWnd, $sb, $sb.Capacity) | Out-Null
        if ($sb.ToString().StartsWith("QuickLook - ")) {
            [Win32]::SetForegroundWindow($hWnd) | Out-Null
            $script:found = $true
            return $false
        }
        return $true
    }, [IntPtr]::Zero) | Out-Null

    if ($found) { break }
    Start-Sleep -Milliseconds 50
}
]])
		f:close()
	end

	-- 2. 将 /tmp 的路径转为 Windows 能够识别的 \\wsl.localhost\... 路径，同样加上单引号包裹
	local tmp_ps_win_path = "'" .. to_win_path(tmp_ps_wsl_path, distro) .. "'"

	-- 3. 使用 os.execute 和末尾的 `&` 符号实现后台异步运行
	-- 加上 -ExecutionPolicy Bypass 增加兼容性，防止 Windows 策略拦截共享目录下的脚本
	local ps_cmd = "pwsh.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File " .. tmp_ps_win_path .. " &"
	os.execute(ps_cmd)

	-- 4. 启动 QuickLook。建议这里末尾也加上 `&` 防止被任何意外情况阻塞 Yazi 主界面
	local ql_cmd = quicklook_exe_wsl .. " " .. file_path_win .. " -top &"
	os.execute(ql_cmd)
end

return M
