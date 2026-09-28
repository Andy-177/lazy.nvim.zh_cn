local ffi = require("ffi")

local M = {}

---@class LazyStats
M._stats = {
  -- 距离 UIEnter 的启动时间（毫秒）
  startuptime = 0,
  -- 为 true 时，startuptime 是 Neovim 进程准确的 CPU 时间（Linux 与 macOS）
  -- 这比 `nvim --startuptime` 更准确，因此数值会略高一些
  -- 为 false 时，startuptime 是根据 lazy 启动时刻的时间戳差值计算得出的
  real_cputime = false,
  count = 0, -- 插件总数
  loaded = 0, -- 已加载的插件数量
  ---@type table<string, number>
  times = {},
}

---@type ffi.namespace*
M.C = nil

function M.on_ui_enter()
  M._stats.startuptime = M.track("UIEnter")
  require("lazy.core.util").track({ start = "startuptime" }, M._stats.startuptime * 1e6)
  vim.api.nvim_exec_autocmds("User", { pattern = "LazyVimStarted", modeline = false })
end

function M.track(event)
  local time = M.cputime()
  M._stats.times[event] = time
  return time
end

function M.cputime()
  if M.C == nil then
    pcall(function()
      ffi.cdef([[
        typedef int clockid_t;
        typedef struct timespec {
          int64_t tv_sec;   /* Use fixed 64-bit type for portability */
          long    tv_nsec;  /* nanoseconds */
        } nanotime;
        int clock_gettime(clockid_t clk_id, struct timespec *tp);
      ]])
      M.C = ffi.C
    end)
  end

  local function real()
    -- 零初始化，以兼容只会写入低 32 位的 32 位系统
    local pnano = ffi.new("nanotime[1]")
    local CLOCK_PROCESS_CPUTIME_ID = jit.os == "OSX" and 12 or 2
    ffi.C.clock_gettime(CLOCK_PROCESS_CPUTIME_ID, pnano)
    return tonumber(pnano[0].tv_sec) * 1e3 + tonumber(pnano[0].tv_nsec) / 1e6
  end

  local function fallback()
    return (vim.uv.hrtime() - require("lazy")._start) / 1e6
  end

  local ok, ret = pcall(real)
  if ok then
    M.cputime = real
    M._stats.real_cputime = true
    return ret
  else
    M.cputime = fallback
    return fallback()
  end
end

function M.stats()
  M._stats.count = 0
  M._stats.loaded = 0
  for _, plugin in pairs(require("lazy.core.config").plugins) do
    M._stats.count = M._stats.count + 1
    if plugin._.loaded then
      M._stats.loaded = M._stats.loaded + 1
    end
  end
  return M._stats
end

return M
