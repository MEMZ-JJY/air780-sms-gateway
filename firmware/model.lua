local model = {}


function model.temp()
    adc.open(adc.CH_CPU)
    local x = adc.get(adc.CH_CPU)
    adc.close(adc.CH_CPU)
    return string.format('%.2f', x / 1000)
end


function model.vbat()
    adc.open(adc.CH_VBAT)
    local x = adc.get(adc.CH_VBAT)
    adc.close(adc.CH_VBAT)
    return string.format('%.2f', x / 1000)
end


function model.os()
    return rtos.firmware()
end


function model.bsp()
    return hmeta.model()
end


function model.hw()
    return hmeta.hwver()
end


function model.chip()
    return hmeta.chip()
end


function model.build()
    local x = rtos.buildDate()
    return x
end


function model.sn()
    return mobile.sn()
end


function model.imei()
    return mobile.imei()
end

return model