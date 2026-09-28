local Config = require("lazy.core.config")
local Pkg = require("lazy.pkg")
local Util = require("lazy.core.util")

--- 这个类用于管理插件。
--- 一个插件是若干彼此相关的片段的集合。
---@class LazyMeta
---@field plugins table<string, LazyPlugin>
---@field str_to_meta table<string, LazyPlugin>
---@field frag_to_meta table<number, LazyPlugin>
---@field dirty table<string, boolean>
---@field spec LazySpecLoader
---@field fragments LazyFragments
---@field pkgs table<string, number>
local M = {}

---@param spec LazySpecLoader
---@return LazyMeta
function M.new(spec)
  local self = setmetatable({}, { __index = M })
  self.spec = spec
  self.fragments = require("lazy.core.fragments").new(spec)
  self.plugins = {}
  self.frag_to_meta = {}
  self.str_to_meta = {}
  self.dirty = {}
  self.pkgs = {}
  return self
end

-- 导入软件包 spec
function M:load_pkgs()
  if not Config.options.pkg.enabled then
    return
  end
  for _, pkg in ipairs(Pkg.get()) do
    local last_id = self.fragments._fid
    local meta, fragment = self:add(pkg.spec)
    if meta and fragment then
      meta._.pkg = pkg
      -- 把所有被添加为可选的顶层软件包片段标记出来
      for _, fid in ipairs(meta._.frags) do
        if fid > last_id then
          local frag = self.fragments:get(fid)
          frag.spec.optional = true
        end
      end
      -- 记录顶层软件包片段
      self.pkgs[pkg.dir] = fragment.id
    end
  end
end

--- 移除一个插件及其所有片段。
---@param name string
function M:del(name)
  local meta = self.plugins[name]
  if not meta then
    return
  end
  for _, fid in ipairs(meta._.frags or {}) do
    self.fragments:del(fid)
  end
  self.plugins[name] = nil
end

--- 把一个片段添加到插件中。
--- 如果插件不存在，将创建一个新插件。
--- 它还会跟踪重命名的情况。
---@param plugin LazyPluginSpec
function M:add(plugin)
  local fragment = self.fragments:add(plugin)
  if not fragment then
    return
  end

  local meta = self.plugins[fragment.name]
    or fragment.url and self.str_to_meta[fragment.url]
    or fragment.dir and self.str_to_meta[fragment.dir]

  if not meta then
    meta = { name = fragment.name, _ = { frags = {} } }
    local url, dir = fragment.url, fragment.dir
    -- 添加到索引
    if url then
      self.str_to_meta[url] = meta
    end
    if dir then
      self.str_to_meta[dir] = meta
    end
  end

  table.insert(meta._.frags, fragment.id)

  if meta._ and meta._.rtp_loaded and meta.dir then
    local old_dir = meta.dir
    self:_rebuild(meta.name)
    local new_dir = meta.dir
    if old_dir ~= new_dir then
      local msg = "插件 `" .. meta.name .. "` 改变了 `dir`：\n- 原来: `" .. old_dir .. "`\n- 现在: `" .. new_dir .. "`"
      msg = msg .. "\n\n该插件已经被部分加载，因此可能会出现问题。\n请修正你的配置。"
      self.spec:error(msg)
    end
  end

  if plugin.name then
    -- 处理重命名
    if meta.name ~= plugin.name then
      self.plugins[meta.name] = nil
      meta.name = plugin.name
    end
  end

  self.plugins[meta.name] = meta
  self.frag_to_meta[fragment.id] = meta
  self.dirty[meta.name] = true
  return meta, fragment
end

--- 基于脏片段或脏插件重建所有插件，
--- 同时会移除那些已不再拥有任何片段的插件。
function M:rebuild()
  local frag_count = vim.tbl_count(self.fragments.dirty)
  local plugin_count = vim.tbl_count(self.dirty)
  if frag_count == 0 and plugin_count == 0 then
    return
  end
  if Config.options.debug then
    Util.track("重建插件 片段数=" .. frag_count .. " 插件数=" .. plugin_count)
  end
  for fid in pairs(self.fragments.dirty) do
    local meta = self.frag_to_meta[fid]
    if meta then
      if self.fragments:get(fid) then
        -- 片段仍然存在，因此把插件标记为脏
        self.dirty[meta.name] = true
      else
        -- 片段已被删除，因此把它从插件中移除
        self.frag_to_meta[fid] = nil
        ---@param f number
        meta._.frags = Util.filter(function(f)
          return f ~= fid
        end, meta._.frags)
        -- 如果没有片段剩下，则删除该插件
        if #meta._.frags == 0 then
          self:del(meta.name)
        else
          self.dirty[meta.name] = true
        end
      end
    end
  end
  self.fragments.dirty = {}
  for n, _ in pairs(self.dirty) do
    self:_rebuild(n)
  end
  if Config.options.debug then
    Util.track()
  end
end

--- 重建单个插件。
--- 这会使用元表根据插件的片段来解析该插件。
--- 同时也会解析 dependencies、dep、optional、dir、dev 和 url。
---@param name string
function M:_rebuild(name)
  if not self.dirty[name] then
    return
  end
  self.dirty[name] = nil
  local plugin = self.plugins[name]
  if not plugin or #plugin._.frags == 0 then
    self.plugins[name] = nil
    return
  end
  setmetatable(plugin, nil)
  plugin.dependencies = {}

  local super = nil
  plugin.url = nil
  plugin._.dep = true
  plugin._.top = true
  plugin.optional = true

  assert(#plugin._.frags > 0, "插件 " .. name .. " 没有找到任何片段")

  ---@type table<number, boolean>
  local added = {}
  for _, fid in ipairs(plugin._.frags) do
    if not added[fid] then
      added[fid] = true
      local fragment = self.fragments:get(fid)
      assert(fragment, "未找到片段 " .. fid .. "，它属于插件 " .. name)
      ---@diagnostic disable-next-line: no-unknown
      super = setmetatable(fragment.spec, super and { __index = super } or nil)
      plugin._.dep = plugin._.dep and fragment.dep
      plugin.optional = plugin.optional and (rawget(fragment.spec, "optional") == true)
      plugin.url = fragment.url or plugin.url
      plugin._.top = plugin._.top and fragment.pid == nil

      -- 依赖
      for _, dep in ipairs(fragment.deps or {}) do
        local dep_meta = self.frag_to_meta[dep]
        if dep_meta then
          table.insert(plugin.dependencies, dep_meta.name)
        end
      end
    end
  end

  super = super or {}

  -- dir / dev
  plugin.dev = super.dev
  plugin.dir = super.dir
  if plugin.dir then
    plugin.dir = Util.norm(plugin.dir)
  elseif super.virtual then
    plugin.dir = Util.norm("/dev/null/" .. plugin.name)
  else
    if plugin.dev == nil and plugin.url then
      for _, pattern in ipairs(Config.options.dev.patterns) do
        if plugin.url:find(pattern, 1, true) then
          plugin.dev = true
          break
        end
      end
    end
    if plugin.dev == true then
      local dev_dir = type(Config.options.dev.path) == "string" and Config.options.dev.path .. "/" .. plugin.name
        or Util.norm(Config.options.dev.path(plugin))
      if not Config.options.dev.fallback or vim.fn.isdirectory(dev_dir) == 1 then
        plugin.dir = dev_dir
      else
        plugin.dev = false
      end
    end
    plugin.dir = plugin.dir or Config.options.root .. "/" .. plugin.name
  end

  -- 依赖
  if #plugin.dependencies == 0 and not super.dependencies then
    plugin.dependencies = nil
  end

  -- 可选
  if not plugin.optional and not super.optional then
    plugin.optional = nil
  end

  setmetatable(plugin, { __index = super })

  return plugin
end

--- 禁用一个插件。
---@param plugin LazyPlugin
function M:disable(plugin)
  plugin._.kind = "disabled"
  self:del(plugin.name)
  self.spec.disabled[plugin.name] = plugin
end

--- 检查插件是否应该被禁用，但忽略卸载它。
function M:fix_cond()
  for _, plugin in pairs(self.plugins) do
    local cond = plugin.cond
    if cond == nil then
      cond = Config.options.defaults.cond
    end
    if cond == false or (type(cond) == "function" and not cond(plugin)) then
      plugin._.cond = false
      local stack = { plugin }
      while #stack > 0 do
        local p = table.remove(stack) --[[@as LazyPlugin]]
        if not self.spec.ignore_installed[p.name] then
          for _, dep in ipairs(p.dependencies or {}) do
            table.insert(stack, self.plugins[dep])
          end
          self.spec.ignore_installed[p.name] = true
        end
      end
      plugin.enabled = false
    end
  end
end

--- 移除那些所有片段都是可选的插件。
function M:fix_optional()
  if self.spec.optional then
    return 0
  end
  local changes = 0
  for _, plugin in pairs(self.plugins) do
    if plugin.optional then
      changes = changes + 1
      self:del(plugin.name)
    end
  end
  self:rebuild()
  return changes
end

--- 移除那些已被禁用的插件。
function M:fix_disabled()
  local changes = 0
  local function check(top)
    for _, plugin in pairs(self.plugins) do
      if (plugin._.top or false) == top then
        if plugin.enabled == false or (type(plugin.enabled) == "function" and not plugin.enabled()) then
          changes = changes + 1
          if plugin.optional then
            self:del(plugin.name)
          else
            self:disable(plugin)
          end
          self:rebuild()
        end
      end
    end
  end
  -- 先禁用顶层插件，因为它们可能含有非顶层片段，
  -- 而这些片段会禁用其他插件
  check(true)
  -- 然后禁用非顶层插件
  check(false)
  return changes
end

--- 移除那些不再使用同一目录的插件的软件包片段。
function M:fix_pkgs()
  for dir, fid in pairs(self.pkgs) do
    local plugin = self.frag_to_meta[fid]
    plugin = plugin and self.plugins[plugin.name]
    if plugin then
      -- 检查该插件是否仍在同一个目录中
      if plugin.dir ~= dir then
        self.fragments:del(fid)
      end
    end
  end
  self:rebuild()
end

--- 根据 cond、enabled 和 optional 解析所有插件。
function M:resolve()
  Util.track("resolve plugins")
  self:rebuild()

  self:fix_pkgs()

  self:fix_cond()

  -- selene: allow(empty_loop)
  while self:fix_disabled() + self:fix_optional() > 0 do
  end
  Util.track()
end

return M
