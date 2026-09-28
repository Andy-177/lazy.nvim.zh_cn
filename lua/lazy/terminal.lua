---@class Ansi: table<string, fun(string):string>
local M = {}

M.colors = {
  reset = "\27[0m",
  black = "\27[30m",
  red = "\27[31m",
  green = "\27[32m",
  yellow = "\27[33m",
  blue = "\27[34m",
  magenta = "\27[35m",
  cyan = "\27[36m",
  white = "\27[37m",
  bright_black = "\27[90m",
  bright_red = "\27[91m",
  bright_green = "\27[92m",
  bright_yellow = "\27[93m",
  bright_blue = "\27[94m",
  bright_magenta = "\27[95m",
  bright_cyan = "\27[96m",
  bright_white = "\27[97m",
}

function M.color(text, color)
  return M.colors[color] .. text .. M.colors.reset
end

-- stylua: ignore start
function M.black(text) return M.color(text, "black") end
function M.red(text) return M.color(text, "red") end
function M.green(text) return M.color(text, "green") end
function M.yellow(text) return M.color(text, "yellow") end
function M.blue(text) return M.color(text, "blue") end
function M.magenta(text) return M.color(text, "magenta") end
function M.cyan(text) return M.color(text, "cyan") end
function M.white(text) return M.color(text, "white") end
function M.bright_black(text) return M.color(text, "bright_black") end
function M.bright_red(text) return M.color(text, "bright_red") end
function M.bright_green(text) return M.color(text, "bright_green") end
function M.bright_yellow(text) return M.color(text, "bright_yellow") end
function M.bright_blue(text) return M.color(text, "bright_blue") end
function M.bright_magenta(text) return M.color(text, "bright_magenta") end
function M.bright_cyan(text) return M.color(text, "bright_cyan") end
function M.bright_white(text) return M.color(text, "bright_white") end
-- stylua: ignore end

---@param data string
---@param prefix string
function M.prefix(data, prefix)
  -- 把 Windows 风格的换行符统一为普通换行符
  data = data:gsub("\r\n", "\n")

  -- 处理第一行的前缀，如果数据是立即开始的话
  data = prefix .. data

  -- 为新行添加前缀，同时避免当某行以 \r 开头时重复添加前缀
  data = data:gsub("(\n)([^\r])", "%1" .. prefix .. "%2")

  -- 正确处理回车符，以避免重复添加前缀
  -- 把任何后面不跟 \n 的 \r 替换为 \r，然后仅当下一个字符不是我们前缀的开头时才添加前缀
  data = data:gsub("\r([^\n])", function(nextChar)
    if nextChar:sub(1, #prefix) == prefix then
      return "\r" .. nextChar
    else
      return "\r" .. prefix .. nextChar
    end
  end)
  return data
end

return M
