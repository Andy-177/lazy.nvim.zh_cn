local Config = require("lazy.core.config")
local Loader = require("lazy.core.loader")
local Util = require("lazy.core.util")

---@class LazyEventOpts
---@field event string
---@field group? string
---@field exclude? string[]
---@field data? any
---@field buffer? number

---@alias LazyEvent {id:string, event:string[]|string, pattern?:string[]|string}
---@alias LazyEventSpec string|{event?:string|string[], pattern?:string|string[]}|string[]

---@class LazyEventHandler:LazyHandler
---@field events table<string,true>
---@field group number
local M = {}

-- 事件依赖关系
M.triggers = {
  FileType = "BufReadPost",
  BufReadPost = "BufReadPre",
}

-- 自定义事件的映射表
-- 发行版可以用它来添加自定义事件（用法参见 LazyVim）
---@type table<string, LazyEvent>
M.mappings = {
  VeryLazy = { id = "VeryLazy", event = "User", pattern = "VeryLazy" },
  -- 示例：
  -- LazyFile = { id = "LazyFile", event = { "BufReadPost", "BufNewFile", "BufWritePre" } },
}
M.mappings["User VeryLazy"] = M.mappings.VeryLazy

M.group = vim.api.nvim_create_augroup("lazy_handler_event", { clear = true })

---@param spec LazyEventSpec
---@return LazyEvent
function M:_parse(spec)
  local ret = M.mappings[spec] --[[@as LazyEvent?]]
  if ret then
    return ret
  end
  if type(spec) == "string" then
    local event, pattern = spec:match("^(%w+)%s+(.*)$")
    event = event or spec
    return { id = spec, event = event, pattern = pattern }
  elseif Util.is_list(spec) then
    ret = { id = table.concat(spec, "|"), event = spec }
  else
    ret = spec --[[@as LazyEvent]]
    if not ret.id then
      ---@diagnostic disable-next-line: assign-type-mismatch, param-type-mismatch
      ret.id = type(ret.event) == "string" and ret.event or table.concat(ret.event, "|")
      if ret.pattern then
        ---@diagnostic disable-next-line: assign-type-mismatch, param-type-mismatch
        ret.id = ret.id .. " " .. (type(ret.pattern) == "string" and ret.pattern or table.concat(ret.pattern, ", "))
      end
    end
  end
  return ret
end

---@param event LazyEvent
function M:_add(event)
  local done = false
  vim.api.nvim_create_autocmd(event.event, {
    group = self.group,
    once = true,
    pattern = event.pattern,
    callback = function(ev)
      if done or not self.active[event.id] then
        return
      end
      -- 变通做法：针对 https://github.com/neovim/neovim/issues/25526 的变通处理
      done = true
      if event.id ~= "VeryLazy" then
        Util.track({ [self.type] = event.id })
      end

      local state = M.get_state(ev.event, ev.buf, ev.data)

      -- 加载插件
      Loader.load(self.active[event.id], { [self.type] = event.id })

      -- 检查是否有插件为这个事件创建了事件处理器，并触发该分组
      for _, s in ipairs(state) do
        M.trigger(s)
      end
      if event.id ~= "VeryLazy" then
        Util.track()
      end
    end,
  })
end

-- 获取当前事件的状态以及所有将被触发的事件
---@param event string
---@param buf number
---@param data any
function M.get_state(event, buf, data)
  local state = {} ---@type LazyEventOpts[]
  while event do
    table.insert(state, 1, {
      event = event,
      exclude = event ~= "FileType" and M.get_augroups(event) or nil,
      buffer = buf,
      data = data,
    })
    data = nil -- 只把 data 传给第一个事件
    event = M.triggers[event]
  end
  return state
end

-- 获取某个事件的所有 augroup
---@param event string
function M.get_augroups(event)
  local groups = {} ---@type string[]
  for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = event })) do
    if autocmd.group_name then
      table.insert(groups, autocmd.group_name)
    end
  end
  return groups
end

-- 触发一个事件。如果给出了 group，则只会触发该分组中的事件。
-- 如果设置了 exclude，则会跳过这些分组中的事件。
---@param opts LazyEventOpts
function M.trigger(opts)
  if opts.group or opts.exclude == nil then
    return M._trigger(opts)
  end
  local done = {} ---@type table<string,true>
  for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = opts.event })) do
    local id = autocmd.event .. ":" .. (autocmd.group or "") ---@type string
    local skip = done[id] or (opts.exclude and vim.tbl_contains(opts.exclude, autocmd.group_name))
    done[id] = true
    if autocmd.group and not skip then
      opts.group = autocmd.group_name
      M._trigger(opts)
    end
  end
end

-- 触发一个事件
---@param opts LazyEventOpts
function M._trigger(opts)
  if Config.options.debug then
    Util.info({
      "# 正在触发事件",
      "  - **event:** " .. opts.event,
      opts.group and ("  - **group:** " .. opts.group),
      opts.buffer and ("  - **buffer:** " .. opts.buffer),
    })
  end
  Util.track({ event = opts.group or opts.event })
  Util.try(function()
    vim.api.nvim_exec_autocmds(opts.event, {
      buffer = opts.buffer,
      group = opts.group,
      modeline = false,
      data = opts.data,
    })
    Util.track()
  end)
end

return M
