local M = {}

---@class LazyViewCommand
---@field id number
---@field plugins? boolean
---@field plugins_required? boolean
---@field button? boolean
---@field desc? string
---@field desc_plugin? string
---@field key? string
---@field key_plugin? string
---@field toggle? boolean

function M.get_commands()
  ---@type (LazyViewCommand|{name:string})[]
  local ret = {}
  for k, v in pairs(M.commands) do
    v.name = k
    ret[#ret + 1] = v
  end
  table.sort(ret, function(a, b)
    return a.id < b.id
  end)
  return ret
end

M.dimmed_commits = { "bot", "build", "ci", "chore", "doc", "style", "test" }

M.keys = {
  hover = "K",
  diff = "d",
  close = "q",
  details = "<cr>",
  profile_sort = "<C-s>",
  profile_filter = "<C-f>",
  abort = "<C-c>",
  next = "]]",
  prev = "[[",
}

---@type table<string,LazyViewCommand>
M.commands = {
  home = {
    button = true,
    desc = "返回插件列表",
    id = 1,
    key = "H",
  },
  install = {
    button = true,
    desc = "安装缺失的插件",
    desc_plugin = "安装插件",
    id = 2,
    key = "I",
    key_plugin = "i",
    plugins = true,
  },
  update = {
    button = true,
    desc = "更新插件。同时也会更新锁定文件",
    desc_plugin = "更新插件。同时也会更新锁定文件",
    id = 3,
    key = "U",
    key_plugin = "u",
    plugins = true,
  },
  sync = {
    button = true,
    desc = "执行安装、清理和更新",
    desc_plugin = "执行安装、清理和更新",
    id = 4,
    key = "S",
    plugins = true,
  },
  clean = {
    button = true,
    desc = "清理不再需要的插件",
    desc_plugin = "删除插件。警告：即使该插件本应被安装，也会被删除！",
    id = 5,
    key = "X",
    key_plugin = "x",
    plugins = true,
  },
  check = {
    button = true,
    desc = "检查更新并显示日志（git fetch）",
    desc_plugin = "检查更新并显示日志（git fetch）",
    id = 6,
    key = "C",
    key_plugin = "c",
    plugins = true,
  },
  log = {
    button = true,
    desc = "显示最近的更新",
    desc_plugin = "显示最近的更新",
    id = 7,
    key = "L",
    key_plugin = "gl",
    plugins = true,
  },
  restore = {
    button = true,
    desc = "将所有插件恢复到锁定文件中的状态。对于单个插件：将其恢复到锁定文件中的状态，或恢复到光标处指定的提交",
    desc_plugin = "将插件恢复到锁定文件中的状态，或恢复到光标处指定的提交",
    id = 8,
    key = "R",
    key_plugin = "r",
    plugins = true,
  },
  profile = {
    button = true,
    desc = "显示详细的性能分析",
    id = 9,
    key = "P",
    toggle = true,
  },
  debug = {
    button = true,
    desc = "显示调试信息",
    id = 10,
    key = "D",
    toggle = true,
  },
  help = {
    button = true,
    desc = "切换此帮助页面",
    id = 11,
    key = "?",
    toggle = true,
  },
  clear = {
    desc = "清除已完成的任务",
    id = 12,
  },
  load = {
    desc = "加载尚未加载的插件。类似于 `:packadd`。例如 `:Lazy load foo.nvim`。使用 `:Lazy! load` 可跳过 `cond` 检查。",
    id = 13,
    plugins = true,
    plugins_required = true,
  },
  health = {
    desc = "运行 `:checkhealth lazy`",
    id = 14,
  },
  build = {
    desc = "重新构建插件",
    id = 15,
    plugins = true,
    plugins_required = true,
    key_plugin = "gb",
  },
  reload = {
    desc = "重新加载插件（实验性功能！！）",
    plugins = true,
    plugins_required = true,
    id = 16,
  },
}

return M
