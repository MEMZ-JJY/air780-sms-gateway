
















local sys = require 'sys'

local sms_at = {}



local nativeSms
do
    local req = require
    local ok, m = pcall(req, 'sms')
    if ok and type(m) == 'table' and type(m.send) == 'function' then
        nativeSms = m
        log.info('sms_at', '检测到原生 sms C 库，优先使用官方实现')
    else
        log.info('sms_at', '无原生 sms 库，启用纯 AT 实现(固件无关)')
    end
end




local function ucs2ToUtf8(hex)
    if not hex or #hex == 0 then return '' end
    
    local raw = hex:gsub('(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
    local out, i = {}, 1
    while i + 1 <= #raw do
        local code = raw:byte(i) * 256 + raw:byte(i + 1)
        i = i + 2
        if code < 0x80 then
            out[#out + 1] = string.char(code)
        elseif code < 0x800 then
            out[#out + 1] = string.char(0xC0 + (code >> 6), 0x80 + (code & 0x3F))
        else
            out[#out + 1] = string.char(0xE0 + (code >> 12), 0x80 + ((code >> 6) & 0x3F), 0x80 + (code & 0x3F))
        end
    end
    return table.concat(out)
end

local function utf8ToUcs2Hex(str)
    local out, i = {}, 1
    while i <= #str do
        local c = str:byte(i)
        local code
        if c < 0x80 then
            code = c; i = i + 1
        elseif c < 0xE0 then
            code = ((c & 0x1F) << 6) + (str:byte(i + 1) & 0x3F); i = i + 2
        else
            code = ((c & 0x0F) << 12) + ((str:byte(i + 1) & 0x3F) << 6) + (str:byte(i + 2) & 0x3F); i = i + 3
        end
        out[#out + 1] = string.format('%04X', code)
    end
    return table.concat(out)
end

local function isAscii(s)
    return not s:find('[^\32-\126]')
end




function sms_at.send(phone, msg, cb)
    if nativeSms then
        local r
        pcall(function() r = nativeSms.send(phone, msg, cb) end)
        return r
    end

    sys.taskInit(function()
        local ok, err = pcall(function()
            if isAscii(msg) then
                mobile.at('AT+CSCS="GSM"', 2000)
                mobile.at('AT+CMGS="' .. phone .. '"', 5000, function(cmd, reply)
                    log.info('sms_at', 'CMGS> ', tostring(reply))
                    if reply and reply:find('>') then
                        mobile.at(msg .. '\x1A', 30000, function(c, r)
                            log.info('sms_at', 'CMGS结果', tostring(r))
                            local done = r and (r:find('CMGS') or r:find('OK'))
                            if cb then cb(done and 0 or -1, r) end
                        end)
                    else
                        log.warn('sms_at', '未等到 > 提示符', tostring(reply))
                        if cb then cb(-1, reply) end
                    end
                end)
            else
                mobile.at('AT+CSCS="UCS2"', 2000)
                mobile.at('AT+CMGS="' .. utf8ToUcs2Hex(phone) .. '"', 5000, function(cmd, reply)
                    log.info('sms_at', 'CMGS> ', tostring(reply))
                    if reply and reply:find('>') then
                        mobile.at(utf8ToUcs2Hex(msg) .. '\x1A', 30000, function(c, r)
                            log.info('sms_at', 'CMGS结果', tostring(r))
                            local done = r and (r:find('CMGS') or r:find('OK'))
                            if cb then cb(done and 0 or -1, r) end
                        end)
                    else
                        log.warn('sms_at', '未等到 > 提示符', tostring(reply))
                        if cb then cb(-1, reply) end
                    end
                end)
            end
        end)
        if not ok then
            log.error('sms_at', '发送异常', tostring(err))
            if cb then cb(-1, err) end
        end
    end)
    return true
end






local function parseCMGL(reply)
    if not reply or #reply == 0 then return end
    local lines = {}
    for line in reply:gmatch('[^\r\n]+') do
        lines[#lines + 1] = line
    end
    for i = 1, #lines do
        
        local idx = lines[i]:match('^+CMGL:%s*(%d+)')
        if idx then
            idx = tonumber(idx)
            local fromHex = lines[i]:match('^+CMGL:%s*%d+,[^,]*,%s*"([^"]*)"')
            local contentHex = lines[i + 1] or ''
            local from = ucs2ToUtf8(fromHex)
            local content = ucs2ToUtf8(contentHex)
            log.info('sms_at', '收到短信', from, content)
            
            sys.publish('SMS_INC', from, content)
            
            pcall(function() mobile.at('AT+CMGD=' .. idx, 3000) end)
        end
    end
end





local pollingStarted = false
local function pollLoop()
    if pollingStarted or nativeSms then return end
    pollingStarted = true
    sys.taskInit(function()
        sys.wait(5000)  
        log.info('sms_at', '注网完成，开始设置短信 AT 参数')
        
        local function atSafe(cmd, t)
            local ok, err = pcall(function() mobile.at(cmd, t or 2000) end)
            log.info('sms_at', 'AT', cmd, ok and 'OK' or ('ERR ' .. tostring(err)))
            return ok
        end
        atSafe('AT+CMGF=1')            
        atSafe('AT+CSCS="UCS2"')       
        atSafe('AT+CNMI=2,1,0,0,0')    
        log.info('sms_at', 'AT短信初始化完成')
        
        pcall(function()
            mobile.at('AT+CSCA?', 3000, function(c, r)
                log.info('sms_at', 'SMSC', tostring(r):gsub('\r?\n', ' '))
            end)
        end)
        
        while true do
            sys.wait(3000)
            pcall(function()
                mobile.at('AT+CMGL="REC UNREAD"', 8000, parseCMGL)
            end)
        end
    end)
    log.info('sms_at', '接收轮询已注册(注网后启动)')
end

function sms_at.init()
    if nativeSms then
        
        log.info('sms_at', '原生库模式，跳过 AT 初始化')
        return
    end
    pollLoop()
end


sys.subscribe('IP_READY',  sms_at.init)
sys.subscribe('SMS_READY', sms_at.init)
sys.timerStart(sms_at.init, 1000 * 60)

return sms_at
