PROJECT = 'Air780EP_SMS'
VERSION = '0.3.88'

log.setLevel(2)
log.style(1)




_G.sys     = require 'sys'
_G.sysplus = require 'sysplus'
_G.config  = require 'config'
_G.led     = require 'led'




local sms = require 'sms_at'
_G.sms = sms


local model    = require 'model'
local sim      = require 'sim'
local params   = require 'params'
local outbox   = require 'outbox'
local commands = require 'commands'
require 'lbs'
require 'subscribe'




if wdt then
    wdt.init(1000 * 9)
    sys.timerLoopStart(wdt.feed, 1000 * 3)
end

if errDump then
    errDump.config(false)
end

pm.force(pm.NONE)
pm.power(pm.GPS, false)
pm.power(pm.GPS_ANT, false)
pm.power(pm.CAMERA, false)

mobile.config(mobile.CONF_STATICCONFIG, 1)
mobile.config(mobile.CONF_QUALITYFIRST, 2)

mobile.ipv6(config.network.IPv6 == 1)
mobile.syncTime(false)
mobile.setAuto(1000 * 10, 1000 * 30, 5)




local statusMap = {
    sim = {
        ['RDY']        = '已经就绪',
        ['NORDY']      = '状态异常',
        ['SIM_PIN']    = '需要验证',
        ['GET_NUMBER'] = '获取号码'
    },
    cc = {
        ['READY']            = '功能就绪',
        ['PLAY']             = '有人致电',
        ['INCOMINGCALL']     = '正在振铃',
        ['ANSWER_CALL_DONE'] = '电话接通',
        ['DISCONNECTED']     = '对方挂断',
        ['HANGUP_CALL_DONE'] = '主动挂断'
    }
}

local network = {
    onl = false,
    dis = 0
}

function isMobile(num)
    return (#num == 11 and num:match('^1[3-9]'))
end

sys.subscribe('ip_reset', function(...)
    if not network.onl then return end
    network = {
        onl = false,
        dis = network.dis + 1
    }
    mobile.reset()
    log.info('IP网络', '重置原因', ..., json.encode(network))
end)

sys.subscribe('ip_wait', function()
    sys.taskInit(function()
        local result = sys.waitUntil('IP_READY', 1000 * 60)
        if not result then
            network.onl = true
            sys.publish('ip_reset', '超时未联网')
        end
        log.info('IP网络', '等待联网', (result and '成功联网' or '超时'))
    end)
end)

sys.subscribe('IP_LOSE', function()
    sys.publish('ip_reset', '断网')
end)

sys.subscribe('SIM_IND', function(status, value)
    if status == 'RDY' then
        sys.publish('ip_wait')
    end
    log.info('SIM卡', statusMap.sim[status] or '未知', status, value)
end)




local http_opt = config.notify.http.options

sys.subscribe('http_notify', function(method, url, headers, body, n)

    if n > http_opt.retry then return end

    sys.taskInit(function()
        log.info('HTTP', url, json.encode(headers), body, string.format('%s/%s', n, http_opt.retry))
        local _, _, _, ipv6 = socket.localIP()
        local  code, _, res = http.request(method, url, headers, body, {
            timeout = http_opt.timeout * 1000,
            debug   = false,
            ipv6    = (ipv6 ~= nil)
        }).wait()
        if code == 200 then
            log.info('HTTP', code, res)
        else
            log.info('HTTP', code, 'error!!!')
            sys.wait(3000)
            sys.publish('http_notify', method, url, headers, body, n + 1)
        end
    end)

end)




local ctrl = {}
if #config.system.ctrl > 0 then
    for _, v in pairs(config.system.ctrl) do
        ctrl[v] = true
    end
end

local http_chl = {}
for key, value in pairs(config.notify.http.channel) do
    if value.enable == 1 then
        table.insert(http_chl, key)
    end
end

sys.subscribe('sms_build_call', function(from)
    local cfg = config.call.reply.sms
    if isMobile(from) and cfg.enable == 1 then
        sys.publish('sms_send', from, string.format(cfg.content, from))
    end
end)


sys.subscribe('sms_build_sms', function(from, content)
    if #config.system.ctrl < 1 or ctrl[from] then
        commands.runLocalCommand(content, function(t) sys.publish('sms_send', from, t) end)
    end
end)

local userAgent = http_opt.ua or string.format('Mozilla/5.0 (%s; %s; %s; %s) %s', model.os(), model.bsp(), model.chip(), model.hw(), model.build())
sys.subscribe('notify_build', function(type, from, content)

    sys.publish('sms_build_' .. type, from, content)

    if #http_chl < 1 then return end

    sys.taskInit(function()
        local num = (type == 'msg') and model.bsp() or sim.num()
        for _, value in ipairs(http_chl) do
            local method, url, headers, body = params[value](type, from, num, content)
            headers['User-Agent'] = userAgent
            sys.publish('http_notify', method, url, headers, body, 1)
        end
    end)

end)

sys.subscribe('IP_READY', function(...)

    if not network.onl then

        log.info('IP网络', '成功联网', ...)
        log.info('IP网络', '网卡详情', socket.localIP())

        network.onl = true

        local dns = config.network.dns
        if #dns < 1 then return end
        for i, ns in ipairs(dns) do
            socket.setDNS(nil, i, ns)
            log.info('DNS', i, ns)
        end

    end

    if config.system.power.notify ~= 1 then return end

    log.info('通知通道', json.encode(http_chl))
    log.info('项目详情', PROJECT, VERSION)

    config.system.power.notify = 0

    local content = {
        string.format('%s设备开机通知', model.bsp()),
        string.format('温度 %s', model.temp()),
        string.format('电压 %s', model.vbat()),
        string.format('IMEI %s', model.imei()),
        string.format('手机号 %s', sim.num()),
        string.format('网络 %s', sim.com() or '已联网'),
        string.format('PLMN %s', sim.plmn()),
        string.format('IMSI %s', mobile.imsi()),
        string.format('ICCID %s', mobile.iccid()),
        string.format('信号 %s dBm', mobile.rsrp())
    }

    sys.publish('notify_build', 'msg', '', table.concat(content, '\r\n'))

end)




sys.subscribe('SMS_INC', function(from, txt)
    log.info('收到短信', from, txt)
    led.event()   
    sys.publish('notify_build', 'sms', from, txt)
end)




local call = {
    incoming = false,
    count    = 0
}
sys.subscribe('CC_IND', function(status)

    local  cfg = config.call.accept
    local from = cc.lastNum()

        if status == 'READY' then cc.init(0)
    elseif status == 'ANSWER_CALL_DONE' then cc.hangUp()
    elseif status == 'DISCONNECTED' or status == 'HANGUP_CALL_DONE' then call = {incoming = false, count = 0}
    elseif status == 'INCOMINGCALL' then

        if not call.incoming then
            sys.publish('notify_build', 'call', from, '来电')
        end

        call = {
            incoming = true,
            count    = call.count + 1
        }

        if call.count == 3 then
            if (isMobile(from) and cfg.M == 1) or cfg.L == 1 then
                cc.accept()
            end
        end

    end
    log.info('通话', statusMap.cc[status] or status, from)

end)




sys.timerLoopStart(sys.publish, 1000 * 30, 'memory_clean')

local power = config.system.power

if power.reboot > 0 then
    sys.timerStart(pm.reboot, 1000 * 60 * 60 * power.reboot)
end

if power.usb ~= 1 then
    sys.timerStart(pm.power, 1000 * 60 * 2, pm.USB, false)
end


if config.notify.outbox and config.notify.outbox.enable == 1 then
    sys.taskInit(outbox.run)
end


sys.timerLoopStart(function()
    if not network.onl then return end
    local ok1, rsrp  = pcall(mobile.rsrp)
    local ok2, csq   = pcall(mobile.csq)
    local ok3, vbat  = pcall(model.vbat)
    local ok4, temp  = pcall(model.temp)
    local ok5, iccid = pcall(mobile.iccid)
    local ok6, num   = pcall(sim.num)
    local method, url, headers, body = params.myHeartbeat(
        ok1 and rsrp or 0, ok2 and csq or 0,
        ok3 and vbat or 0, ok4 and tostring(temp) or '',
        ok5 and iccid or '', ok6 and num or '', model.bsp())
    if method and headers then
        headers['User-Agent'] = userAgent
        sys.publish('http_notify', method, url, headers, body, 1)
    end
end, 1000 * 60 * 5)



sys.timerStart(commands.smsClearStorage, 10000)
sys.timerLoopStart(commands.smsClearStorage, 1000 * 60 * 30)

sys.run()
