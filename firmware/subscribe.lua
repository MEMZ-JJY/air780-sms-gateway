
sys.subscribe('memory_clean', function()
    collectgarbage('collect')
end)


sys.subscribe('http_build', function()
    sys.publish('memory_clean')
end)


sys.subscribe('http_notify', function()
    led.event()
end)


sys.subscribe('IP_READY', function()
    led.network(1)
end)


sys.subscribe('IP_LOSE', function()
    led.network(0)
end)


sys.subscribe('sms_send', function(num, txt)
    log.info('发出短信', num, txt)
    sms.send(num, txt)
end)
