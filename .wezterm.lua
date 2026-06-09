local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- 1. 环境与路径
config.default_cwd = "D:/Alicia/ExoCore_Project"
config.default_prog = {
  'C:/Program Files/Git/bin/bash.exe',
  '--login',
}

-- 2. Windows 专属高拟真磨砂质感 (Acrylic / Mica)
config.win32_system_backdrop = 'Acrylic'
config.window_background_opacity = 0.88
config.text_background_opacity = 1.0

-- 3. 字体与排版
config.font = wezterm.font('Cascadia Code', { weight = 'Regular' })
config.font_size = 12.0
config.line_height = 1.15

-- 4. ExoCore 专属主权视觉配色 (Obsidian & Crimson Laser)
config.colors = {
  foreground = '#C8D3F5',       -- 柔和冷灰文字
  background = '#0A0B10',       -- ExoCore 深邃曜石底色
  cursor_bg = '#FF2E2E',        -- 暗红激光光标
  cursor_fg = '#0A0B10',
  cursor_border = '#FF2E2E',
  selection_bg = '#451010',     -- 选区：暗红熔岩高亮
  selection_fg = '#FFFFFF',
  split = '#1F202F',            -- 边框：暗铁色
  
  -- 终端 ANSI 标准 16 色调校
  ansi = {
    '#1E1E2E', -- black
    '#FF3B30', -- red
    '#4EAF70', -- green
    '#E0AF68', -- yellow
    '#3B82F6', -- blue
    '#BB9AF7', -- magenta
    '#0DB9D7', -- cyan
    '#A9B1D6', -- white
  },
  brights = {
    '#565F89', -- bright black
    '#FF605C', -- bright red
    '#73D216', -- bright green
    '#F2CA30', -- bright yellow
    '#70A1FF', -- bright blue
    '#D0B0FF', -- bright magenta
    '#56E2F5', -- bright cyan
    '#FFFFFF', -- bright white
  },

  -- 标签栏视觉强化
  tab_bar = {
    background = '#06070A',
    active_tab = {
      bg_color = '#250808',     -- 激活标签页：深邃暗红底
      fg_color = '#FF2E2E',     -- 亮红文字
      intensity = 'Bold',
    },
    inactive_tab = {
      bg_color = '#0F1015',     -- 未激活：暗铁底色
      fg_color = '#565F89',     -- 灰暗文字
    },
    inactive_tab_hover = {
      bg_color = '#1A1C23',
      fg_color = '#C8D3F5',
    },
    new_tab = {
      bg_color = '#0F1015',
      fg_color = '#565F89',
    },
    new_tab_hover = {
      bg_color = '#1A1C23',
      fg_color = '#C8D3F5',
    },
  },
}

-- 5. 标签栏 (Tab Bar) 全局行为
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false
config.use_fancy_tab_bar = false -- 扁平化无缝设计

-- 6. 窗口布局与无边框设计
config.window_padding = {
  left = 12,
  right = 12,
  top = 10,
  bottom = 10,
}
config.window_decorations = "RESIZE" -- 移除厚重的 Windows 默认标题栏，保留缩放边框

-- 7. 激活窗格边框强化 (Active Pane Border)
config.active_pane_ids = true
-- 动态设置窗格边框颜色（激活时亮红，未激活时暗铁）
wezterm.on('update-status', function(window, pane)
  -- 可以在此动态注入右侧状态栏
end)

-- 8. 进程退出行为
config.exit_behavior = 'Hold'

-- 9. 核心快捷键
config.keys = {
  {
    key = 'p',
    mods = 'ALT',
    action = wezterm.action.PaneSelect { mode = 'Activate' },
  },
  {
    key = 'd',
    mods = 'ALT',
    action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' },
  },
  {
    key = 's',
    mods = 'ALT',
    action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' },
  },
}

return config