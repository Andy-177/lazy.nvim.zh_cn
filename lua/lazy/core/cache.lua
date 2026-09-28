local uv = vim.uv or vim.loop

local M = {}

---@alias CacheHash {mtime: {sec:number, nsec:number}, size:number}
---@alias CacheEntry {hash:CacheHash, chunk:string}

---@class ModuleFindOpts
---@field all? boolean 搜索所有匹配项（默认为 `false`）
---@field rtp? boolean 在运行时路径中搜索 modname（默认为 `true`）
---@field patterns? string[] 要使用的模式（默认为 `{"/init.lua", ".lua"}`）
---@field paths? string[] 用于搜索 modname 的额外路径

---@class ModuleInfo
---@field modpath string 模块的路径
---@field modname string 模块的名称
---@field stat? uv_fs_t 模块路径的文件状态

---@alias LoaderStats table<string, {total:number, time:number, [string]:number?}?>

M.path = vim.fn.stdpath("cache") .. "/luac"
M.enabled = false

---@class Loader
---@field _rtp string[]
---@field _rtp_pure string[]
---@field _rtp_key string
local Loader = {
  VERSION = 3,
  ---@type table<string, table<string,ModuleInfo>>
  _indexed = {},
  ---@type table<string, string[]>
  _topmods = {},
  _loadfile = loadfile,
  ---@type LoaderStats
  _stats = {
    find = { total = 0, time = 0, not_found = 0 },
  },
}

--- 跟踪在函数中花费的时间
---@private
function Loader.track(stat, start)
  Loader._stats[stat] = Loader._stats[stat] or { total = 0, time = 0 }
  Loader._stats[stat].total = Loader._stats[stat].total + 1
  Loader._stats[stat].time = Loader._stats[stat].time + uv.hrtime() - start
end

--- 比 vim.fs.normalize 稍快/略有不同的版本
--- 我们也必须在这里实现它，因为 loader 会加载 vim.fs
---@private
function Loader.normalize(path)
  if path:sub(1, 1) == "~" then
    local home = uv.os_homedir() or "~"
    if home:sub(-1) == "\\" or home:sub(-1) == "/" then
      home = home:sub(1, -2)
    end
    path = home .. path:sub(2)
  end
  path = path:gsub("\\", "/"):gsub("/+", "/")
  return path:sub(-1) == "/" and path:sub(1, -2) or path
end

--- 获取不包含 after 目录的 rtp。
--- 结果会被缓存，并在运行时路径变化时更新。
--- 当从快速事件中调用时，将返回缓存的值。
--- @return string[] rtp, boolean 是否已更新
---@private
function Loader.get_rtp()
  local start = uv.hrtime()
  if vim.in_fast_event() then
    Loader.track("get_rtp", start)
    return (Loader._rtp or {}), false
  end
  local updated = false
  local key = vim.go.rtp
  if key ~= Loader._rtp_key then
    Loader._rtp = {}
    for _, path in ipairs(vim.api.nvim_get_runtime_file("", true)) do
      path = Loader.normalize(path)
      -- 跳过 after 目录
      if path:sub(-6, -1) ~= "/after" and not (Loader._indexed[path] and vim.tbl_isempty(Loader._indexed[path])) then
        Loader._rtp[#Loader._rtp + 1] = path
      end
    end
    updated = true
    Loader._rtp_key = key
  end
  Loader.track("get_rtp", start)
  return Loader._rtp, updated
end

--- 返回缓存文件名
---@param name string 可以是模块名，也可以是文件名
---@return string file_name
---@private
function Loader.cache_file(name)
  local ret = M.path .. "/" .. name:gsub("[/\\:]", "%%")
  return ret:sub(-4) == ".lua" and (ret .. "c") or (ret .. ".luac")
end

--- 保存某个模块或文件的缓存条目
---@param name string 模块名或文件名
---@param entry CacheEntry
---@private
function Loader.write(name, entry)
  local cname = Loader.cache_file(name)
  local f = assert(uv.fs_open(cname, "w", 438))
  local header = {
    Loader.VERSION,
    entry.hash.size,
    entry.hash.mtime.sec,
    entry.hash.mtime.nsec,
  }
  uv.fs_write(f, table.concat(header, ",") .. "\0")
  uv.fs_write(f, entry.chunk)
  uv.fs_close(f)
end

--- 加载某个模块或文件的缓存条目
---@param name string 模块名或文件名
---@return CacheEntry?
---@private
function Loader.read(name)
  local start = uv.hrtime()
  local cname = Loader.cache_file(name)
  local f = uv.fs_open(cname, "r", 438)
  if f then
    local hash = uv.fs_fstat(f) --[[@as CacheHash]]
    local data = uv.fs_read(f, hash.size, 0) --[[@as string]]
    uv.fs_close(f)

    local zero = data:find("\0", 1, true)
    if not zero then
      return
    end

    ---@type integer[]|{[0]:integer}
    local header = vim.split(data:sub(1, zero - 1), ",")
    if tonumber(header[1]) ~= Loader.VERSION then
      return
    end
    Loader.track("read", start)
    return {
      hash = { size = tonumber(header[2]), mtime = { sec = tonumber(header[3]), nsec = tonumber(header[4]) } },
      chunk = data:sub(zero + 1),
    }
  end
  Loader.track("read", start)
end

--- 使用缓存的 lua 文件 `package.loaders` 加载器
---@param modname string 模块名
---@return string|function
---@private
function Loader.loader(modname)
  local start = uv.hrtime()
  local ret = M.find(modname)[1]
  if ret then
    local chunk, err = Loader.load(ret.modpath, { hash = ret.stat })
    Loader.track("loader", start)
    return chunk or error(err)
  end
  Loader.track("loader", start)
  return "\ncache_loader: module " .. modname .. " not found"
end

--- 库的 `package.loaders` 加载器
---@param modname string 模块名
---@return string|function
---@private
function Loader.loader_lib(modname)
  local start = uv.hrtime()
  local sysname = uv.os_uname().sysname:lower() or ""
  local is_win = sysname:find("win", 1, true) and not sysname:find("darwin", 1, true)
  local ret = M.find(modname, { patterns = is_win and { ".dll" } or { ".so" } })[1]
  ---@type function?, string?
  if ret then
    -- 在 Lua 5.1 中生成函数名（参见 src/loadlib.c:mkfuncname）的方式是
    -- a) 去掉前缀直到第一个短横线（如果有）为止
    -- b) 把所有点替换为下划线
    -- c) 在前面加上 "luaopen_"
    -- 所以 "foo-bar.baz" 应该得到 "luaopen_bar_baz"
    local dash = modname:find("-", 1, true)
    local funcname = dash and modname:sub(dash + 1) or modname
    local chunk, err = package.loadlib(ret.modpath, "luaopen_" .. funcname:gsub("%.", "_"))
    Loader.track("loader_lib", start)
    return chunk or error(err)
  end
  Loader.track("loader_lib", start)
  return "\ncache_loader_lib: module " .. modname .. " not found"
end

--- 使用缓存的 `loadfile`
---@param filename? string
---@param mode? "b"|"t"|"bt"
---@param env? table
---@param hash? CacheHash
---@return function?, string?  error_message
---@private
-- luacheck: ignore 312
function Loader.loadfile(filename, mode, env, hash)
  local start = uv.hrtime()
  filename = Loader.normalize(filename)
  mode = nil -- 忽略 mode，因为我们会对 lua 源文件做字节码编译
  local chunk, err = Loader.load(filename, { mode = mode, env = env, hash = hash })
  Loader.track("loadfile", start)
  return chunk, err
end

--- 根据以下内容检查两个缓存哈希是否相同：
--- * 文件大小
--- * 以秒为单位的 mtime
--- * 以纳秒为单位的 mtime
---@param h1 CacheHash
---@param h2 CacheHash
---@private
function Loader.eq(h1, h2)
  return h1 and h2 and h1.size == h2.size and h1.mtime.sec == h2.mtime.sec and h1.mtime.nsec == h2.mtime.nsec
end

--- 使用缓存加载给定的模块路径
---@param modpath string
---@param opts? {hash?: CacheHash, mode?: "b"|"t"|"bt", env?:table} (table|nil) 加载模块的选项：
---    - hash: (table) 若已知，则为要加载文件的哈希值。（默认为 `vim.uv.fs_stat({modpath})`）
---    - mode: (string) 加载模块所用的模式。"b"|"t"|"bt"（默认为 `nil`）
---    - env: (table) 加载模块所处的环境。（默认为 `nil`）
---@see |luaL_loadfile()|
---@return function?, string? error_message
---@private
function Loader.load(modpath, opts)
  local start = uv.hrtime()

  opts = opts or {}
  local hash = opts.hash or uv.fs_stat(modpath)
  ---@type function?, string?
  local chunk, err

  if not hash then
    -- 触发正确的错误
    chunk, err = Loader._loadfile(modpath, opts.mode, opts.env)
    Loader.track("load", start)
    return chunk, err
  end

  local entry = Loader.read(modpath)
  if entry and Loader.eq(entry.hash, hash) then
    -- 在缓存中找到且是最新的
    -- selene: allow(incorrect_standard_library_use)
    chunk, err = load(entry.chunk --[[@as string]], "@" .. modpath, opts.mode, opts.env)
    if not (err and err:find("cannot load incompatible bytecode", 1, true)) then
      Loader.track("load", start)
      return chunk, err
    end
  end
  entry = { hash = hash, modpath = modpath }

  chunk, err = Loader._loadfile(modpath, opts.mode, opts.env)
  if chunk then
    entry.chunk = string.dump(chunk)
    Loader.write(modpath, entry)
  end
  Loader.track("load", start)
  return chunk, err
end

--- 查找与给定模块名对应的 lua 模块。
---@param modname string 模块名，或 `"*"` 表示改为查找顶层模块
---@param opts? ModuleFindOpts (table|nil) 查找模块的选项：
---    - rtp: (boolean) 在运行时路径中查找 modname（默认为 `true`）
---    - paths: (string[]) 用于查找 modname 的额外路径（默认为 `{}`）
---    - patterns: (string[]) 查找模块时使用的模式列表。
---                模式是一个字符串，会追加到正在查找的 lua 模块的基本名之后。
---                （默认为 `{"/init.lua", ".lua"}`）
---    - all: (boolean) 返回所有匹配项，而不只是第一个（默认为 `false`）
---@return ModuleInfo[] (list) 具有以下属性的结果列表：
---    - modpath: (string) 模块的路径
---    - modname: (string) 模块的名称
---    - stat: (table|nil) 模块路径的 fs_stat。当 `modname="*"` 时不会返回
function M.find(modname, opts)
  local start = uv.hrtime()
  opts = opts or {}

  modname = modname:gsub("/", ".")
  local basename = modname:gsub("%.", "/")
  local idx = modname:find(".", 1, true)

  -- 变通做法：修正错误的 require 语句。我真的不太喜欢保留这个处理，
  -- 但显然常规的 lua 加载器也允许这样做
  if idx == 1 then
    modname = modname:gsub("^%.+", "")
    basename = modname:gsub("%.", "/")
    idx = modname:find(".", 1, true)
  end

  -- 得到顶层模块名
  local topmod = idx and modname:sub(1, idx - 1) or modname

  -- 优化：当 topmod == modname 时优先搜索目录
  local patterns = opts.patterns or (topmod == modname and { "/init.lua", ".lua" } or { ".lua", "/init.lua" })
  for p, pattern in ipairs(patterns) do
    patterns[p] = "/lua/" .. basename .. pattern
  end

  ---@type ModuleInfo[]
  local results = {}

  -- 只有在还没找到任何内容、或者我们想要找到全部时才继续
  ---@private
  local function continue()
    return #results == 0 or opts.all
  end

  -- 检查给定的路径是否包含顶层模块。
  -- 如果是，则尝试为给定的模块名查找模块路径。
  ---@param paths string[]
  ---@private
  local function _find(paths)
    for _, path in ipairs(paths) do
      if topmod == "*" then
        for _, r in pairs(Loader.lsmod(path)) do
          results[#results + 1] = r
          if not continue() then
            return
          end
        end
      elseif Loader.lsmod(path)[topmod] then
        for _, pattern in ipairs(patterns) do
          local modpath = path .. pattern
          Loader._stats.find.stat = (Loader._stats.find.stat or 0) + 1
          local hash = uv.fs_stat(modpath)
          if hash then
            results[#results + 1] = { modpath = modpath, stat = hash, modname = modname }
            if not continue() then
              return
            end
          end
        end
      end
    end
  end

  -- 总是先检查 rtp
  if opts.rtp ~= false then
    _find(Loader._rtp or {})
    if continue() then
      local rtp, updated = Loader.get_rtp()
      if updated then
        _find(rtp)
      end
    end
  end

  -- 检查任何额外的路径
  if continue() and opts.paths then
    _find(opts.paths)
  end

  Loader.track("find", start)
  if #results == 0 then
    -- 未找到模块
    Loader._stats.find.not_found = Loader._stats.find.not_found + 1
  end

  return results
end

--- 重置该路径（或所有路径）的 topmods 缓存
--- 当 path 为 nil 时。
---@param path string? 要重置的路径
function M.reset(path)
  if path then
    Loader._indexed[Loader.normalize(path)] = nil
  else
    Loader._indexed = {}
  end
end

--- 启用实验性的 Lua 模块加载器：
--- * 覆盖 loadfile
--- * 添加使用字节码编译缓存的 lua 加载器
--- * 添加库的加载器
--- * 移除 Neovim 默认的加载器
function M.enable()
  if M.enabled then
    return
  end
  M.enabled = true
  vim.fn.mkdir(vim.fn.fnamemodify(M.path, ":p"), "p")
  -- selene: allow(global_usage)
  _G.loadfile = Loader.loadfile
  -- 添加 lua 加载器
  table.insert(package.loaders, 2, Loader.loader)
  -- 添加库加载器
  table.insert(package.loaders, 3, Loader.loader_lib)
  -- 移除 Neovim 加载器
  for l, loader in ipairs(package.loaders) do
    if loader == vim._load_package then
      table.remove(package.loaders, l)
      break
    end
  end

  -- 这会重置 top-mods，以防有人向已在 rtp 中的路径
  -- 添加了新的顶层 lua 模块
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("cache_topmods_reset", { clear = true }),
    callback = function(event)
      local bufname = event.match ---@type string
      local idx = bufname:find("/lua/", 1, true)
      if idx then
        M.reset(bufname:sub(1, idx - 1))
      end
    end,
  })
end

--- 禁用实验性的 Lua 模块加载器：
--- * 移除这些加载器
--- * 添加回 Neovim 默认的加载器
function M.disable()
  if not M.enabled then
    return
  end
  M.enabled = false
  -- selene: allow(global_usage)
  _G.loadfile = Loader._loadfile
  ---@diagnostic disable-next-line: no-unknown
  for l, loader in ipairs(package.loaders) do
    if loader == Loader.loader or loader == Loader.loader_lib then
      table.remove(package.loaders, l)
    end
  end
  table.insert(package.loaders, 2, vim._load_package)
  vim.api.nvim_del_augroup_by_name("cache_topmods_reset")
end

--- 返回该路径顶层的 `/lua/*` 模块
---@param path string 用于检查顶层 lua 模块的路径
---@private
function Loader.lsmod(path)
  if not Loader._indexed[path] then
    local start = uv.hrtime()
    Loader._indexed[path] = {}
    local handle = uv.fs_scandir(path .. "/lua")
    while handle do
      local name, t = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      local modpath = path .. "/lua/" .. name
      -- 变通做法：由于 luv 的 bug，type 有时不会被返回
      t = t or uv.fs_stat(modpath).type
      ---@type string
      local topname
      local ext = name:sub(-4)
      if ext == ".lua" or ext == ".dll" then
        topname = name:sub(1, -5)
      elseif name:sub(-3) == ".so" then
        topname = name:sub(1, -4)
      elseif t == "link" or t == "directory" then
        topname = name
      end
      if topname then
        Loader._indexed[path][topname] = { modpath = modpath, modname = topname }
        Loader._topmods[topname] = Loader._topmods[topname] or {}
        if not vim.tbl_contains(Loader._topmods[topname], path) then
          table.insert(Loader._topmods[topname], path)
        end
      end
    end
    Loader.track("lsmod", start)
  end
  return Loader._indexed[path]
end

--- 调试用函数，包装所有加载器并跟踪统计数据
---@private
function M._profile_loaders()
  for l, loader in pairs(package.loaders) do
    local loc = debug.getinfo(loader, "Sn").source:sub(2)
    package.loaders[l] = function(modname)
      local start = uv.hrtime()
      local ret = loader(modname)
      Loader.track("loader " .. l .. ": " .. loc, start)
      Loader.track("loader_all", start)
      return ret
    end
  end
end

--- 打印所有缓存统计信息
---@param opts? {print?:boolean}
---@return LoaderStats
---@private
function M._inspect(opts)
  if opts and opts.print then
    ---@private
    local function ms(nsec)
      return math.floor(nsec / 1e6 * 1000 + 0.5) / 1000 .. "ms"
    end
    local chunks = {} ---@type string[][]
    ---@type string[]
    local stats = vim.tbl_keys(Loader._stats)
    table.sort(stats)
    for _, stat in ipairs(stats) do
      vim.list_extend(chunks, {
        { "\n" .. stat .. "\n", "Title" },
        { "* 总数:    " },
        { tostring(Loader._stats[stat].total) .. "\n", "Number" },
        { "* 耗时:     " },
        { ms(Loader._stats[stat].time) .. "\n", "Bold" },
        { "* 平均耗时: " },
        { ms(Loader._stats[stat].time / Loader._stats[stat].total) .. "\n", "Bold" },
      })
      for k, v in pairs(Loader._stats[stat]) do
        if not vim.tbl_contains({ "time", "total" }, k) then
          chunks[#chunks + 1] = { "* " .. k .. ":" .. string.rep(" ", 9 - #k) }
          chunks[#chunks + 1] = { tostring(v) .. "\n", "Number" }
        end
      end
    end
    vim.api.nvim_echo(chunks, true, {})
  end
  return Loader._stats
end

return M
