local Async = require("lazy.async")
local Config = require("lazy.core.config")
local Git = require("lazy.manage.git")
local Lock = require("lazy.manage.lock")
local Util = require("lazy.util")

local throttle = {}
throttle.running = 0
throttle.waiting = {} ---@type Async[]
throttle.timer = vim.uv.new_timer()

function throttle.next()
  throttle.running = 0
  while #throttle.waiting > 0 and throttle.running < Config.options.git.throttle.rate do
    ---@type Async
    local task = table.remove(throttle.waiting, 1)
    task:resume()
    throttle.running = throttle.running + 1
  end
  if throttle.running == 0 then
    throttle.timer:stop()
  end
end

function throttle.wait()
  if not Config.options.git.throttle.enabled then
    return
  end
  if not throttle.timer:is_active() then
    throttle.timer:start(0, Config.options.git.throttle.duration, vim.schedule_wrap(throttle.next))
  end
  local running = Async.running()
  if throttle.running < Config.options.git.throttle.rate then
    throttle.running = throttle.running + 1
  else
    table.insert(throttle.waiting, running)
    coroutine.yield("waiting")
    running:suspend()
    coroutine.yield("")
  end
end

---@param plugin LazyPlugin
local function cooldown(plugin)
  if not plugin._.last_check then
    return false
  end
  local delta = (vim.uv.now() - plugin._.last_check) / 1000
  return delta < Config.options.git.cooldown
end

---@type table<string, LazyTaskDef>
local M = {}

M.log = {
  ---@param opts {updated?:boolean, check?: boolean}
  skip = function(plugin, opts)
    if opts.check and plugin.pin then
      return true
    end
    if opts.updated and not (plugin._.updated and plugin._.updated.from ~= plugin._.updated.to) then
      return true
    end
    local stat = vim.uv.fs_stat(plugin.dir .. "/.git")
    return not (stat and stat.type == "directory")
  end,
  ---@async
  ---@param opts {args?: string[], updated?:boolean, check?:boolean}
  run = function(self, opts)
    -- self:spawn({ "sleep", "5" })
    local args = {
      "log",
      "--pretty=format:%h %s (%cr)",
      "--abbrev-commit",
      "--decorate",
      "--date=short",
      "--color=never",
      "--no-show-signature",
    }

    local info, target

    if opts.updated then
      table.insert(args, self.plugin._.updated.from .. ".." .. (self.plugin._.updated.to or "HEAD"))
    elseif opts.check then
      info = assert(Git.info(self.plugin.dir))
      target = assert(Git.get_target(self.plugin))
      if not target.commit then
        for k, v in pairs(target) do
          error("未找到 " .. k .. " '" .. v .. "'")
        end
        error("未找到目标提交")
      end
      assert(target.commit, self.plugin.name .. " " .. target.branch)
      if not self.plugin._.is_local then
        if Git.eq(info, target) then
          if Config.options.checker.check_pinned then
            local last_commit = Git.get_commit(self.plugin.dir, target.branch, true)
            if not Git.eq(info, { commit = last_commit }) then
              self.plugin._.outdated = true
            end
          end
        else
          self.plugin._.updates = { from = info, to = target }
        end
      end
      table.insert(args, info.commit .. ".." .. target.commit)
    else
      vim.list_extend(args, opts.args or Config.options.git.log)
    end

    self:spawn("git", {
      args = args,
      cwd = self.plugin.dir,
    })

    -- 对本地插件，只有当本地落后于上游时才标记为需要更新，
    -- 也就是当 git log 没有输出时
    if opts.check and self.plugin._.is_local then
      if not vim.tbl_isempty(self:get_log()) then
        self.plugin._.updates = { from = info, to = target }
      end
    end
  end,
}

M.clone = {
  skip = function(plugin)
    return plugin._.installed or plugin._.is_local
  end,
  ---@async
  run = function(self)
    throttle.wait()
    local args = {
      "clone",
      self.plugin.url,
    }

    if Config.options.git.filter then
      args[#args + 1] = "--filter=blob:none"
    end

    if self.plugin.submodules ~= false then
      args[#args + 1] = "--recurse-submodules"
    end

    args[#args + 1] = "--origin=origin"

    -- 如果在 Unix/Linux 系统上 git config --global core.autocrlf 为 true，
    -- 那么 git clone 过程会导致文件带有 CRLF 换行符。
    -- 而 Vi / vim / neovim 无法处理这种情况。
    -- 因此强制 git 以 core.autocrlf=false 进行克隆。
    args[#args + 1] = "-c"
    args[#args + 1] = "core.autocrlf=false"

    args[#args + 1] = "--progress"

    if self.plugin.branch then
      vim.list_extend(args, { "-b", self.plugin.branch })
    end

    table.insert(args, self.plugin.dir)

    if vim.fn.isdirectory(self.plugin.dir) == 1 then
      require("lazy.manage.task.fs").clean.run(self, {})
    end

    local marker = self.plugin.dir .. ".cloning"
    Util.write_file(marker, "")

    self:spawn("git", {
      args = args,
      on_exit = function(ok)
        if ok then
          self.plugin._.cloned = true
          self.plugin._.installed = true
          self.plugin._.dirty = true
          vim.uv.fs_unlink(marker)
        end
      end,
    })
  end,
}

-- 如果需要则设置 origin 分支
-- fetch 会获取相应数据
M.branch = {
  skip = function(plugin)
    if not plugin._.installed or plugin._.is_local then
      return true
    end
    local branch = assert(Git.get_branch(plugin))
    return Git.get_commit(plugin.dir, branch, true)
  end,
  ---@async
  run = function(self)
    local args = {
      "remote",
      "set-branches",
      "--add",
      "origin",
      assert(Git.get_branch(self.plugin)),
    }

    self:spawn("git", {
      args = args,
      cwd = self.plugin.dir,
    })
  end,
}

-- 检查并切换 origin
M.origin = {
  skip = function(plugin)
    if not plugin._.installed or plugin._.is_local then
      return true
    end
    local origin = Git.get_origin(plugin.dir)
    return origin == plugin.url
  end,
  ---@async
  ---@param opts {check?:boolean}
  run = function(self, opts)
    if opts.check then
      local origin = Git.get_origin(self.plugin.dir)
      self:error({
        "origin 已经改变：",
        "  * 旧值: " .. origin,
        "  * 新值: " .. self.plugin.url,
        "请运行 update 来修复",
      })
      return
    end
    require("lazy.manage.task.fs").clean.run(self, opts)
    M.clone.run(self, opts)
  end,
}

M.status = {
  skip = function(plugin)
    return not plugin._.installed or plugin._.is_local
  end,
  ---@async
  run = function(self)
    self:spawn("git", {
      args = { "ls-files", "-d", "-m" },
      cwd = self.plugin.dir,
      on_exit = function(ok, output)
        if ok then
          local lines = vim.split(output, "\n")
          ---@type string[]
          lines = vim.tbl_filter(function(line)
            -- 修正 doc/tags 被标记为已修改的问题
            if line:gsub("[\\/]", "/") == "doc/tags" then
              local Process = require("lazy.manage.process")
              Process.exec({ "git", "checkout", "--", "doc/tags" }, { cwd = self.plugin.dir })
              return false
            end
            return line ~= ""
          end, lines)
          if #lines > 0 then
            local msg = { "在 `" .. self.plugin.dir .. "` 中存在本地改动：" }
            for _, line in ipairs(lines) do
              msg[#msg + 1] = "  * " .. line
            end
            msg[#msg + 1] = "请移除这些改动后再更新。"
            msg[#msg + 1] = "你也可以按 `x` 删除该插件，然后按 `I` 重新安装。"
            self:error(msg)
          end
        end
      end,
    })
  end,
}

-- 获取所有需要的 origin 分支
M.fetch = {
  skip = function(plugin)
    return not plugin._.installed or plugin._.is_local or cooldown(plugin)
  end,

  ---@async
  run = function(self)
    throttle.wait()
    local args = {
      "fetch",
      "--recurse-submodules",
      "--tags", -- 同时获取远程标签
      "--force", -- 必要时覆盖已有标签
      "--progress",
    }

    if self.plugin.submodules == false then
      table.remove(args, 2)
    end

    self:spawn("git", {
      args = args,
      cwd = self.plugin.dir,
      on_exit = function(ok)
        if ok then
          self.plugin._.last_check = vim.uv.now()
        end
      end,
    })
  end,
}

-- 检出到目标提交
-- 到这一步分支和提交都已经存在
M.checkout = {
  skip = function(plugin)
    return not plugin._.installed or plugin._.is_local
  end,

  ---@async
  ---@param opts {lockfile?:boolean}
  run = function(self, opts)
    throttle.wait()
    local info = assert(Git.info(self.plugin.dir))
    local target = assert(Git.get_target(self.plugin))

    -- 如果插件被锁定（pin）且我们不是刚刚克隆的，
    -- 那么就不更新
    if self.plugin.pin and not self.plugin._.cloned then
      target = info
    end

    local lock
    if opts.lockfile then
      -- 如果锁定记录存在，则还原到该状态
      lock = Lock.get(self.plugin)
      if lock then
        ---@diagnostic disable-next-line: cast-local-type
        target = lock
      end
    end

    -- 如果已经处于目标状态，则不要运行 checkout。
    -- 除非刚刚克隆过，因为那时我们还没有任何数据
    if Git.eq(info, target) and info.branch == target.branch then
      self.plugin._.updated = {
        from = info.commit,
        to = info.commit,
      }
      return
    end

    local args = {
      "checkout",
      "--progress",
      "--recurse-submodules",
    }

    if self.plugin.submodules == false then
      table.remove(args, 3)
    end

    if lock then
      table.insert(args, lock.commit)
    elseif target.tag then
      table.insert(args, "tags/" .. target.tag)
    elseif self.plugin.commit then
      table.insert(args, self.plugin.commit)
    else
      table.insert(args, target.commit)
    end

    self:spawn("git", {
      args = args,
      cwd = self.plugin.dir,
      on_exit = function(ok)
        if ok then
          local new_info = assert(Git.info(self.plugin.dir))
          if not self.plugin._.cloned then
            self.plugin._.updated = {
              from = info.commit,
              to = new_info.commit,
            }
            if self.plugin._.updated.from ~= self.plugin._.updated.to then
              self.plugin._.dirty = true
            end
          end
        end
      end,
    })
  end,
}
return M
