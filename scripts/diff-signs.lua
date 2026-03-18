-- diff-signs.lua — places git diff signs (+/-) in the current buffer's gutter
-- Sourced by nvim-open.sh after each Write/Edit hook via --remote-send / -c

local bufnr = vim.api.nvim_get_current_buf()
local filepath = vim.api.nvim_buf_get_name(bufnr)
if filepath == '' then return end

-- Define signs once per session
if vim.fn.sign_getdefined('ClaudeAdd')[1] == nil then
    vim.fn.sign_define('ClaudeAdd',    { text = '+', texthl = 'DiffAdd' })
    vim.fn.sign_define('ClaudeDelete', { text = '-', texthl = 'DiffDelete' })
end

-- Clear previous Claude diff signs for this buffer
vim.fn.sign_unplace('ClaudeDiff', { buffer = bufnr })

-- Get diff vs HEAD; fall back to /dev/null for new/untracked files
local diff = vim.fn.system('git diff HEAD -- ' .. vim.fn.shellescape(filepath) .. ' 2>/dev/null')
if diff == '' then
    diff = vim.fn.system('git diff --no-index -- /dev/null ' .. vim.fn.shellescape(filepath) .. ' 2>/dev/null')
end
if diff == '' then return end

-- Parse unified diff hunks
local new_line = 0
for line in (diff .. '\n'):gmatch('([^\n]*)\n') do
    local ns = line:match('^@@ %-%d+,?%d* %+(%d+)[,%d]* @@')
    if ns then
        new_line = tonumber(ns)
    elseif line:sub(1, 1) == '+' and line:sub(1, 3) ~= '+++' then
        pcall(vim.fn.sign_place, 0, 'ClaudeDiff', 'ClaudeAdd', bufnr,
            { lnum = new_line, priority = 10 })
        new_line = new_line + 1
    elseif line:sub(1, 1) == '-' and line:sub(1, 3) ~= '---' then
        -- Deletion: mark at the surrounding line (can't point below the file)
        pcall(vim.fn.sign_place, 0, 'ClaudeDiff', 'ClaudeDelete', bufnr,
            { lnum = math.max(1, new_line), priority = 10 })
    elseif line:sub(1, 1) ~= '\\' then
        -- Context line (or diff header) — advance new-file counter
        new_line = new_line + 1
    end
end
