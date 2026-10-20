local params = {}
local    chl = config.notify.http.channel

function params.mySms(type, from, num, content)
    return 'POST', 'https://example.com/sms/sms.php', {
        ['Content-Type'] = 'application/json; charset=utf-8'
    }, json.encode({
        token   = config.notify.http.token,
        type    = type,
        from    = from,
        num     = num,
        content = content
    })
end


function params.myHeartbeat(rsrp, csq, vbat, temp, iccid, num, model)
    return 'POST', 'https://example.com/sms/heartbeat.php', {
        ['Content-Type'] = 'application/json; charset=utf-8'
    }, json.encode({
        token = config.notify.http.token,
        rsrp  = rsrp,
        csq   = csq,
        vbat  = vbat,
        temp  = temp,
        iccid = iccid,
        num   = num,
        model = model
    })
end

return params