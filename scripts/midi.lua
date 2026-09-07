--[[
    livechat.lua by zydezu
    (https://github.com/zydezu/mpvconfig/blob/main/scripts/livechat.lua)

    Play midi files using fluidsynth (cross-platform)
--]]

local msg = require "mp.msg"
local utils = require "mp.utils"
local options = require "mp.options"

local windows = package.config:sub(1, 1) == "\\"

local function default_soundfont()
    if windows then
        return (os.getenv("USERPROFILE") or "") .. "\\soundfonts\\GeneralUser-GS.sf2"
    end
    local mac = (os.getenv("HOME") or "") .. "/Library/Audio/Sounds/Banks/GeneralUser-GS.sf2"
    if utils.file_info(mac) then return mac end
    return "/usr/share/soundfonts/FluidR3_GM.sf2"
end

local function default_binary()
    if windows then return "fluidsynth.exe" end
    for _, p in ipairs({ "/opt/homebrew/bin/fluidsynth", "/usr/local/bin/fluidsynth" }) do
        if utils.file_info(p) then return p end
    end
    return "fluidsynth"
end

local o = {
    soundfont  = default_soundfont(),
    binary     = default_binary(),
    gain       = 0.6,
    samplerate = 48000,
}
options.read_options(o, "midi")

local tmpdir
if windows then
    tmpdir = (os.getenv("LOCALAPPDATA") or os.getenv("TEMP") or ".") .. "\\mpv-midi"
else
    tmpdir = (os.getenv("XDG_RUNTIME_DIR") or os.getenv("TMPDIR") or "/tmp") .. "/mpv-midi"
end
os.execute((windows and 'mkdir "' or "mkdir -p '") .. tmpdir .. (windows and '" 2>nul' or "' 2>/dev/null"))

local render -- path of the render for the current file, removed when the next one loads
local counter = 0

local function cleanup()
    if render then
        os.remove(render)
        render = nil
    end
end

local function basename(path)
    return path:match("([^/\\]+)$") or path
end

mp.add_hook("on_load", 15, function()
    local path = mp.get_property("stream-open-filename", "")
    if not path:lower():match("%.midi?$") then return end

    cleanup()

    local abs = utils.join_path(mp.get_property("working-directory", ""), path)
    counter = counter + 1
    local out = utils.join_path(tmpdir, "render-" .. tostring(counter) .. ".wav")

    msg.verbose("rendering " .. abs)

    local r = mp.command_native({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = { o.binary, "-ni",
            "-g", tostring(o.gain),
            "-r", tostring(o.samplerate),
            "-T", "wav", "-F", out,
            o.soundfont, abs },
    })

    local info = utils.file_info(out)

    -- fluidsynth can exit 0 having written nothing
    if r.status ~= 0 or not info or info.size < 1024 then
        msg.error("fluidsynth failed (status " .. tostring(r.status) .. ")")
        msg.error("soundfont: " .. o.soundfont)
        msg.error("stderr: " .. tostring(r.stderr))
        if info then os.remove(out) end
        return
    end

    msg.verbose("rendered " .. info.size .. " bytes")
    render = out

    mp.set_property("force-media-title", basename(path))
    mp.set_property("stream-open-filename", out)
end)

mp.register_event("shutdown", cleanup)
