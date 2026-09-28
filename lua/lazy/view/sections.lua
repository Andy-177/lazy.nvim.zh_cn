---@param plugin LazyPlugin
---@param filter fun(task:LazyTask):boolean?
local function has_task(plugin, filter)
  if plugin._.tasks then
    for _, task in ipairs(plugin._.tasks) do
      if filter(task) then
        return true
      end
    end
  end
end

---@alias LazySection {title:string, filter:fun(plugin:LazyPlugin):boolean?}

---@type LazySection[]
return {
  {
    filter = function(plugin)
      return has_task(plugin, function(task)
        return task:has_errors()
      end)
    end,
    title = "失败",
  },
  {
    filter = function(plugin)
      if plugin._.working then
        return true
      end
      return has_task(plugin, function(task)
        return task:running()
      end)
    end,
    title = "进行中",
  },
  {
    filter = function(plugin)
      return plugin._.build
    end,
    title = "构建",
  },
  {
    filter = function(plugin)
      return has_task(plugin, function(task)
        if task.name ~= "log" then
          return
        end
        for _, line in ipairs(vim.split(task:output(), "\n")) do
          if line:find("^%w+ %S+!:") then
            return true
          end
        end
      end)
    end,
    title = "破坏性变更",
  },
  {
    filter = function(plugin)
      return plugin._.updated and plugin._.updated.from ~= plugin._.updated.to
    end,
    title = "已更新",
  },
  {
    filter = function(plugin)
      return plugin._.cloned
    end,
    title = "已安装",
  },
  {
    ---@param plugin LazyPlugin
    filter = function(plugin)
      return plugin._.updates ~= nil
    end,
    title = "可更新",
  },
  {
    filter = function(plugin)
      return has_task(plugin, function(task)
        return task.name == "log" and vim.trim(task:output()) ~= ""
      end)
    end,
    title = "日志",
  },
  {
    filter = function(plugin)
      return plugin._.kind == "clean" and plugin._.installed
    end,
    title = "待清理",
  },
  {
    filter = function(plugin)
      return not plugin._.installed and plugin._.kind ~= "disabled"
    end,
    title = "未安装",
  },
  {
    filter = function(plugin)
      return plugin._.outdated
    end,
    title = "已过时",
  },
  {
    filter = function(plugin)
      return plugin._.loaded ~= nil
    end,
    title = "已加载",
  },
  {
    filter = function(plugin)
      return plugin._.installed
    end,
    title = "未加载",
  },
  {
    filter = function(plugin)
      return plugin._.kind == "disabled"
    end,
    title = "已禁用",
  },
}
