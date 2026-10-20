




local lbs = {}


local function firstCell()
    local ok, info = pcall(mobile.getCellInfo)
    if not ok or type(info) ~= 'table' or #info == 0 then return nil end
    local c = info[1]
    return {
        mcc = c.mcc or c.MCC,
        mnc = c.mnc or c.MNC,
        lac = c.lac or c.LAC,
        ci  = c.cellid or c.CI or c.cellId,
    }
end


function lbs.locate(cb)
    sys.taskInit(function()
        local c = firstCell()
        if not c then
            cb('定位失败：无小区信息')
            return
        end

        
        local url = string.format(
            'http://api.cellocation.com:81/cell/?mcc=%s&mnc=%s&lac=%s&ci=%s&coord=gcj02&output=json',
            tostring(c.mcc or ''), tostring(c.mnc or ''),
            tostring(c.lac or ''), tostring(c.ci  or ''))

        local code, _, body = http.request('GET', url, nil, nil, { timeout = 8000 }).wait()

        local addr = ''
        if code == 200 and body and #body > 0 then
            local ok, j = pcall(json.decode, body)
            if ok and type(j) == 'table' then
                addr = tostring(j.address or '')
            end
        end

        if addr ~= '' and addr ~= 'nil' then
            cb('位置: ' .. addr)
        else
            cb(string.format('小区: MCC%s MNC%s LAC%s CELL%s',
                tostring(c.mcc or '?'), tostring(c.mnc or '?'),
                tostring(c.lac or '?'), tostring(c.ci  or '?')))
        end
    end)
end

return lbs
