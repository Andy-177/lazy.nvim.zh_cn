local Config = require("lazy.core.config")
local Util = require("lazy.core.util")

--- 这个类用于管理插件 spec 的各个片段（fragment）。
--- 它记录这些片段以及它们与其他片段之间的关系。
--- 一个片段可以是另一个片段的依赖（dependencies），也可以是它的子 spec（specs）。
---@class LazyFragments
---@field fragments table<number, LazyFragment>
---@field frag_stack number[]
---@field dep_stack number[]
---@field dirty table<number, boolean>
---@field plugins table<LazyPlugin, number>
---@field spec LazySpecLoader
local M = {}

M._fid = 0

local function next_id()
  M._fid = M._fid + 1
  return M._fid
end

---@param spec LazySpecLoader
---@return LazyFragments
function M.new(spec)
  local self = setmetatable({}, { __index = M })
  self.fragments = {}
  self.frag_stack = {}
  self.dep_stack = {}
  self.spec = spec
  self.dirty = {}
  self.plugins = {}
  return self
end

---@param id number
function M:get(id)
  return self.fragments[id]
end

--- 移除一个片段及其所有子片段。
--- 这也会把该片段从其父片段的子列表中移除。
---@param id number
function M:del(id)
  -- 删除片段
  local fragment = self.fragments[id]
  if not fragment then
    return
  end

  self.dirty[id] = true

  -- 从父片段中移除
  local pid = fragment.pid
  if pid then
    local parent = self.fragments[pid]
    if parent.frags then
      ---@param fid number
      parent.frags = Util.filter(function(fid)
        return fid ~= id
      end, parent.frags)
    end
    if parent.deps then
      ---@param fid number
      parent.deps = Util.filter(function(fid)
        return fid ~= id
      end, parent.deps)
    end
    self.dirty[pid] = true
  end

  -- 移除子片段
  if fragment.frags then
    for _, fid in ipairs(fragment.frags) do
      self:del(fid)
    end
  end

  self.fragments[id] = nil
end

--- 把一个片段添加到片段列表中。
--- 这也会解析它的 name、url、dir、依赖以及子 spec。
---@param plugin LazyPluginSpec
function M:add(plugin)
  if self.plugins[plugin] then
    return self.fragments[self.plugins[plugin]]
  end

  local id = next_id()
  setmetatable(plugin, nil)

  self.plugins[plugin] = id

  local pid = self.frag_stack[#self.frag_stack]

  ---@type LazyFragment
  local fragment = {
    id = id,
    pid = pid,
    name = plugin.name,
    url = plugin.url,
    dir = plugin.dir,
    spec = plugin --[[@as LazyPlugin]],
  }

  -- 短 url / ref
  if plugin[1] then
    local slash = plugin[1]:find("/", 1, true)
    if slash then
      local prefix = plugin[1]:sub(1, 4)
      if prefix == "http" or prefix == "git@" then
        fragment.url = fragment.url or plugin[1]
      else
        fragment.name = fragment.name or plugin[1]:sub(slash + 1)
        fragment.url = fragment.url or Config.options.git.url_format:format(plugin[1])
      end
    else
      fragment.name = fragment.name or plugin[1]
    end
  end

  -- 名称
  fragment.name = fragment.name
    or fragment.url and self.spec.get_name(fragment.url)
    or fragment.dir and self.spec.get_name(fragment.dir)
  if not fragment.name or fragment.name == "" then
    return self.spec:error("无效的插件 spec " .. vim.inspect(plugin))
  end

  if type(plugin.config) == "table" then
    self.spec:warn(
      "{" .. fragment.name .. "}: 给 `Plugin.config` 赋一个 table 已被弃用，请改用 `Plugin.opts`"
    )
    ---@diagnostic disable-next-line: assign-type-mismatch
    plugin.opts = plugin.config
    plugin.config = nil
  end

  self.fragments[id] = fragment

  -- 添加到父片段
  if pid then
    local parent = self.fragments[pid]
    parent.frags = parent.frags or {}
    table.insert(parent.frags, id)
  end

  -- 添加到父片段的依赖中
  local did = self.dep_stack[#self.dep_stack]
  if did and did == pid then
    fragment.dep = true
    local parent = self.fragments[did]
    parent.deps = parent.deps or {}
    table.insert(parent.deps, id)
  end

  table.insert(self.frag_stack, id)
  -- 依赖
  if plugin.dependencies then
    table.insert(self.dep_stack, id)
    self.spec:normalize(plugin.dependencies)
    table.remove(self.dep_stack)
  end
  -- 子 spec
  if plugin.specs then
    self.spec:normalize(plugin.specs)
  end
  table.remove(self.frag_stack)

  return fragment
end

return M
