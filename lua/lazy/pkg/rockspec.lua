--# selene:allow(incorrect_standard_library_use)
local Community = require("lazy.community")

local Config = require("lazy.core.config")
local Health = require("lazy.health")
local Util = require("lazy.util")

---@class RockSpec
---@field rockspec_format string
---@field package string
---@field version string
---@field dependencies string[]
---@field build? {type?: string, modules?: any[]}
---@field source? {url?: string}

---@class RockManifest
---@field repository table<string, table<string,any>>

local M = {}

M.skip = { "lua" }
M.rewrites = {
  ["plenary.nvim"] = { "nvim-lua/plenary.nvim", lazy = true },
}

M.python = { "python3", "python" }

---@class HereRocks
M.hererocks = {}

---@param task LazyTask
function M.hererocks.build(task)
  local root = Config.options.rocks.root .. "/hererocks"

  ---@param p string
  local python = vim.tbl_filter(function(p)
    return vim.fn.executable(p) == 1
  end, M.python)[1]

  task:spawn(python, {
    args = {
      "hererocks.py",
      "--verbose",
      "-l",
      "5.1",
      "-r",
      "latest",
      root,
    },
    cwd = task.plugin.dir,
  })
end

---@param bin string
function M.hererocks.bin(bin)
  local hererocks = Config.options.rocks.root .. "/hererocks/bin"
  return Util.norm(hererocks .. "/" .. bin)
end

-- 检查 hererocks 是否正在构建
---@return boolean?
function M.hererocks.building()
  return vim.tbl_get(Config.plugins.hererocks or {}, "_", "build")
end

---@param opts? LazyHealth
function M.check(opts)
  opts = vim.tbl_extend("force", {
    error = Util.error,
    warn = Util.warn,
    ok = function() end,
  }, opts or {})

  local ok = false
  if Config.hererocks() then
    if M.hererocks.building() then
      ok = true
    else
      ok = Health.have(M.python, opts)
      ok = Health.have(M.hererocks.bin("luarocks")) and ok
      Health.have(
        M.hererocks.bin("lua"),
        vim.tbl_extend("force", opts, {
          version = "-v",
          version_pattern = "5.1",
        })
      )
    end
  else
    ok = Health.have("luarocks", opts)
    Health.have(
      { "lua5.1", "lua", "lua-5.1" },
      vim.tbl_extend("force", opts, {
        version = "-v",
        version_pattern = "5.1",
      })
    )
  end
  return ok
end

---@async
---@param task LazyTask
function M.build(task)
  M.check({
    error = function(msg)
      task:error(msg:gsub("[{}]", "`"))
    end,
    warn = function(msg)
      task:warn(msg)
    end,
    ok = function(msg) end,
  })

  if task:has_warnings() then
    task:log({
      "",
      "该插件需要 `luarocks`。请尝试以下方法之一：",
      " - 修复你的 `luarocks` 安装",
      Config.hererocks() and " - 用 `opts.rocks.hererocks = false` 禁用 *hererocks*"
        or " - 用 `opts.rocks.hererocks = true` 启用 `hererocks`",
      " - 用 `opts.rocks.enabled = false` 完全禁用 `luarocks` 支持",
    })
    task:warn("\n仍会尝试进行构建，但很可能失败……")

    task:warn("\n" .. string.rep("-", 80) .. "\n")

    task:set_level(vim.log.levels.WARN)
  end

  if task.plugin.name == "hererocks" then
    return M.hererocks.build(task)
  end

  local env = {}
  local luarocks = "luarocks"
  if Config.hererocks() then
    -- hererocks 仍在构建中，所以暂时跳过
    -- 下一轮会进行新的构建
    if M.hererocks.building() then
      return
    end

    local sep = Util.is_win and ";" or ":"
    local hererocks = Config.options.rocks.root .. "/hererocks/bin"
    if Util.is_win then
      hererocks = hererocks:gsub("/", "\\")
    end
    local path = vim.split(vim.env.PATH, sep)
    table.insert(path, 1, hererocks)
    env = {
      PATH = table.concat(path, sep),
    }
    if Util.is_win then
      luarocks = luarocks .. ".bat"
    end
  end

  local pkg = task.plugin._.pkg
  assert(pkg, "插件 " .. task.plugin.name .. " 缺少 rockspec pkg\n这不应该发生，请反馈。")

  local rockspec = M.rockspec(task.plugin.dir .. "/" .. pkg.file) or {}
  assert(
    rockspec.package,
    "插件 " .. task.plugin.name .. " 缺少 rockspec 包名\n这不应该发生，请反馈。"
  )

  local root = Config.options.rocks.root .. "/" .. task.plugin.name
  local ok = task:spawn(luarocks, {
    args = {
      "--tree",
      root,
      "--server",
      Config.options.rocks.server,
      "--lua-version",
      "5.1",
      "install", -- use install so that we can make use of pre-built rocks
      "--force-fast",
      "--deps-mode",
      "one",
      rockspec.package,
    },
    cwd = task.plugin.dir,
    env = env,
  })

  if ok then
    return
  end

  task:warn("使用 `luarocks` 安装 " .. rockspec.package .. " 失败。")
  task:warn("\n" .. string.rep("-", 80) .. "\n")
  task:warn("正在尝试从源码构建。")

  -- 安装失败，因此尝试从源码构建
  task:set_level() -- 重置层级
  ok = task:spawn(luarocks, {
    args = {
      "--tree",
      root,
      "--dev",
      "--lua-version",
      "5.1",
      "make",
      "--force-fast",
      "--deps-mode",
      "one",
    },
    cwd = task.plugin.dir,
    env = env,
  })
  if not ok then
    require("lazy.manage.task.fs").clean.run(task, { rocks_only = true })
  end
end

---@param rockspec RockSpec
function M.is_simple_build(rockspec)
  local type = vim.tbl_get(rockspec, "build", "type")
  return type == nil or type == "none" or (type == "builtin" and not rockspec.build.modules)
end

---@param file string
---@return table?
function M.parse(file)
  local ret = {}
  local ok = pcall(function()
    loadfile(file, nil, ret)()
  end) and ret or nil
  return ok and ret or nil
end

---@param plugin LazyPlugin
function M.deps(plugin)
  local root = Config.options.rocks.root .. "/" .. plugin.name
  ---@type RockManifest?
  local manifest = M.parse(root .. "/lib/luarocks/rocks-5.1/manifest")
  return manifest and vim.tbl_keys(manifest.repository or {})
end

---@param file string
---@return RockSpec?
function M.rockspec(file)
  return M.parse(file)
end

---@param plugin LazyPlugin
function M.find_rockspec(plugin)
  local rockspec_file ---@type string?
  Util.ls(plugin.dir, function(path, name, t)
    if t == "file" then
      for _, suffix in ipairs({ "scm", "git", "dev" }) do
        suffix = suffix .. "-1.rockspec"
        if name:sub(-#suffix) == suffix then
          rockspec_file = path
          return false
        end
      end
    end
  end)
  return rockspec_file
end

---@param plugin LazyPlugin
---@return LazyPkgSpec?
function M.get(plugin)
  if Community.get_spec(plugin.name) then
    return {
      file = "community",
      source = "lazy",
      spec = Community.get_spec(plugin.name),
    }
  end

  local rockspec_file = M.find_rockspec(plugin)
  local rockspec = rockspec_file and M.rockspec(rockspec_file)
  if not rockspec then
    return
  end

  local has_lua = not not vim.uv.fs_stat(plugin.dir .. "/lua")

  ---@type LazyPluginSpec
  local specs = {}

  ---@param dep string
  local rocks = vim.tbl_filter(function(dep)
    local name = dep:match("^%s*([^~><=%s]+)")
    if not name then
      return false
    end
    local url = Community.get_url(name)
    local spec = Community.get_spec(name)

    if spec then
      -- 社区 spec
      table.insert(specs, spec)
      return false
    elseif url then
      -- Neovim 插件 rock
      table.insert(specs, { url })
      return false
    end
    return not vim.tbl_contains(M.skip, name)
  end, rockspec.dependencies or {})

  local use =
    -- 不带 /lua 目录的软件包
    not has_lua
    -- 存在未被跳过、
    -- 不在社区 spec 中、
    -- 且没有 rockspec 映射的依赖
    or #rocks > 0
    -- 拥有复杂的构建流程
    or not M.is_simple_build(rockspec)

  if not use then
    -- 只使用社区 spec
    return #specs > 0
        and {
          file = vim.fn.fnamemodify(rockspec_file, ":t"),
          spec = {
            plugin.name,
            specs = specs,
            build = false,
          },
        }
      or nil
  end

  local lazy = nil
  if not has_lua then
    lazy = false
  end

  return {
    file = vim.fn.fnamemodify(rockspec_file, ":t"),
    spec = {
      plugin.name,
      build = "rockspec",
      lazy = lazy,
    },
  }
end

return M
