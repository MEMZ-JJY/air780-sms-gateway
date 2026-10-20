








local config = require 'config'
local commands = require 'commands'

local M = {}

local cfg    = config.notify.outbox or {}
local token  = config.notify.http.token
local url    = cfg.url or ''
local period = (cfg.interval or 60) * 1000

local function http_json(method, body)
    if url == '' then return nil, -1 end
    local code, _, res = http.request(method, url, {
        ['Content-Type'] = 'application/json; charset=utf-8'
    }, json.encode(body), { timeout = 10000 }).wait()
    if code ~= 200 then return nil, code end
    local ok, data = pcall(json.decode, res or '')
    if not ok or type(data) ~= 'table' then return nil, code end
    return data, code
end


local function postCmdResult(id, result)
    if url == '' then return end
    local code, _, res = http.request('POST', url, {
        ['Content-Type'] = 'application/json; charset=utf-8'
    }, json.encode({ token = token, id = id, action = 'cmd_done', result = tostring(result or '') }), { timeout = 10000 }).wait()
    log.info('outbox', '指令回执', id, code, tostring(result):sub(1, 60))
end


function M.tick()
    local data, code = http_json('GET', { token = token })
    if not data then
        log.info('outbox', '取件失败', code)
        return 0
    end

    local items = data.items or {}
    if #items < 1 then return 0 end

    local sent = 0
    for _, it in ipairs(items) do
        local typ = it.type or 'sms'
        if typ == 'cmd' and it.cmd then
            
            local id = it.id
            local reported = false
            local function rep(t)
                reported = true
                pcall(postCmdResult, id, tostring(t or ''))
            end
            pcall(commands.runLocalCommand, it.cmd, rep)
            if not reported then
                
                pcall(postCmdResult, id, '已执行')
            end
            sent = sent + 1
            sys.wait(200)
        else
            local num  = it.num or ''
            local txt  = it.content or ''
            if num ~= '' and txt ~= '' then

                log.info('outbox', '发出', num, txt)

                
                
                local accepted = false
                pcall(function()
                    sms.send(num, txt, function(result, ...)
                        log.info('outbox', '发送结果', tostring(result), '->', num)
                    end)
                    accepted = true
                end)
                if accepted then
                    pcall(function()
                        http_json('POST', { token = token, id = it.id })
                    end)
                    sent = sent + 1
                else
                    log.info('outbox', '发送失败，下轮重试', num)
                end

                sys.wait(500)
            end
        end
    end

    if sent > 0 then log.info('outbox', '本轮发出', sent) end
    return sent
end


function M.run()
    while true do
        sys.waitUntil('IP_READY', 1000 * 60 * 5)
        log.info('outbox', '开始轮询', url, (cfg.interval or 60) .. 's')
        while true do
            M.tick()
            if sys.waitUntil('IP_LOSE', period) then break end
        end
        log.info('outbox', '等待联网')
    end
end

return M
