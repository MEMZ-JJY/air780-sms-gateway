









local sys   = require 'sys'
local model = require 'model'
local sim   = require 'sim'
local led   = require 'led'
local lbs   = require 'lbs'


local gpioReserved = { [27] = 1, [30] = 1 }


local function smsClearStorage()
    pcall(function()
        mobile.at('AT+CMGD=1,4', 3000, function(cmd, reply)
            log.info('短信箱', '已清理', tostring(reply))
        end)
    end)
end


local function deviceStatusText()
    local ok1, rsrp = pcall(mobile.rsrp)
    local ok2, vbat = pcall(model.vbat)
    local ok3, temp = pcall(model.temp)
    local ok4, num  = pcall(sim.num)
    return table.concat({
        '设备状态',
        string.format('信号 %s dBm', ok1 and rsrp or '?'),
        string.format('电压 %s',     ok2 and vbat or '?'),
        string.format('温度 %s',     ok3 and temp or '?'),
        string.format('网络 %s',     sim.com() or '已联网'),
        string.format('号码 %s',     ok4 and num or '?'),
        string.format('IMEI %s',     model.imei()),
    }, '\r\n')
end




local cmds = {}

cmds.help = function(parts, content, report)
    report(
指令一览（发 ##help 查看本列表）：
##sms##号##内容       代发短信
##stat [号]           设备状态
##loc [号]            基站定位
##net                 网络/运营商信息
##volt                电压/温度
##led##on|off|blink   指示灯
##gpio##脚##on|off|get  控/读 GPIO
##ping##host[:port]   连通性探测
##echo##文本          回显测试
##smsclear            清理短信箱
##reboot              远程重启)
end


cmds.sms = function(parts, content, report)
    if #parts > 2 and tonumber(parts[2]) then
        local msg = content:sub(#parts[1] + #parts[2] + 7)
        if msg ~= '' then
            sys.publish('sms_send', parts[2], msg)
            report('已代发短信至 ' .. parts[2])
        else
            report('用法: ##sms##号##内容')
        end
    else
        report('用法: ##sms##号##内容')
    end
end


cmds.stat = function(parts, content, report)
    report(deviceStatusText())
end


cmds.loc = function(parts, content, report)
    lbs.locate(function(txt) report(txt) end)
end


cmds.net = function(parts, content, report)
    local ok1, rsrp = pcall(mobile.rsrp)
    local ok2, csq  = pcall(mobile.csq)
    local ip = { socket.localIP() }
    report(table.concat({
        '网络信息',
        string.format('运营商 %s', sim.com() or '已联网'),
        string.format('PLMN %s',  tostring(sim.plmn())),
        string.format('IMEI %s',  model.imei()),
        string.format('ICCID %s', mobile.iccid()),
        string.format('信号 %s dBm / CSQ %s', ok1 and rsrp or '?', ok2 and csq or '?'),
        string.format('本机IP %s', tostring(ip[1] or ip[3] or '?')),
    }, '\r\n'))
end


cmds.volt = function(parts, content, report)
    report(table.concat({
        '电压温度',
        string.format('电压 %s V',  model.vbat()),
        string.format('温度 %s ℃', model.temp()),
    }, '\r\n'))
end


cmds.led = function(parts, content, report)
    local act = (parts[2] or ''):lower()
    if act == 'on' then        led.network(1); report('网络指示灯 已亮')
    elseif act == 'off' then   led.network(0); report('网络指示灯 已灭')
    elseif act == 'blink' then led.event();    report('指示灯 闪烁中')
    else report('用法: ##led##on|off|blink')
    end
end


cmds.gpio = function(parts, content, report)
    local pin = tonumber(parts[2])
    local act = (parts[3] or ''):lower()
    if not pin then report('用法: ##gpio##脚号##on|off|get'); return end
    if gpioReserved[pin] then report(string.format('GPIO%d 系统保留(LED)不可控', pin)); return end
    local ok, f
    if act == 'get' then
        ok, f = pcall(gpio.setup, pin, nil, gpio.PULLUP)
    else
        ok, f = pcall(gpio.setup, pin, 0)
    end
    if not ok or type(f) ~= 'function' then
        report('GPIO 初始化失败: ' .. tostring(f))
        return
    end
    if act == 'get' then
        report(string.format('GPIO%d 电平 %s', pin, tostring(f())))
    else
        f(act == 'on' and 1 or 0)
        report(string.format('GPIO%d 已置 %s', pin, act == 'on' and '高(1)' or '低(0)'))
    end
end


cmds.ping = function(parts, content, report)
    local arg = parts[2] or ''
    local host, port = arg:match('^(.-):?(%d*)$')
    port = tonumber(port) or 80
    if host == '' then report('用法: ##ping##host[:port]'); return end
    report(string.format('正在探测 %s:%d …', host, port))
    sys.taskInit(function()
        local c = socket.tcp()
        if c.timeout then c:timeout(8000) end
        local r = pcall(function() return c:connect(host, port) end)
        c:close()
        local ok = (r == true)
        report(string.format('ping %s:%d %s', host, port, ok and '可达' or '不可达/超时'))
    end)
end


cmds.echo = function(parts, content, report)
    report('回显: ' .. (parts[2] or ''))
end


cmds.smsclear = function(parts, content, report)
    smsClearStorage()
    report('短信箱已清理，请稍后测试收发')
end


cmds.reboot = function(parts, content, report)
    report('设备即将重启…')
    sys.timerStart(rtos.reboot, 1500)
end


cmds.call = function(parts, content, report)
    if parts[2] and tonumber(parts[2]) then
        local ok, cc = pcall(require, 'cc')
        if ok and cc then
            report('正在拨打 ' .. parts[2])
            cc.call(parts[2])
        else
            report('本设备未启用通话模块')
        end
    else
        report('用法: ##call##号码')
    end
end





local function runLocalCommand(text, report)
    if type(text) ~= 'string' or not text:find('##', 1, true) then
        return false
    end
    local parts = {}
    for part in text:gmatch('([^##]+)') do
        table.insert(parts, part)
    end
    local cmd = (parts[1] or ''):lower()
    local handler = cmds[cmd]
    if handler then
        local ok, err = pcall(handler, parts, text, report)
        if not ok then
            log.error('指令', cmd, err)
            pcall(report, '指令[' .. cmd .. ']执行出错: ' .. tostring(err))
        end
    else
        pcall(report, '未知指令: ' .. cmd .. '（发 ##help 查看）')
    end
    return true
end

return {
    runLocalCommand = runLocalCommand,
    smsClearStorage = smsClearStorage,
}
