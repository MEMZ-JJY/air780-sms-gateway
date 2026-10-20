return {
    network = {
        dns = {
            '180.184.2.2',
            '223.5.5.5'
        },
        IPv6 = 0
    },
    notify = {
        http = {
            
            token   = 'CHANGE_ME',
            options = {
                timeout = 8,
                retry   = 10,
                ua      = nil
            },
            channel = {
                mySms = {
                    enable = 1
                }
            }
        },
        
        outbox = {
            enable   = 1,
            url      = 'https://example.com/sms/outbox.php',
            interval = 60
        }
    },
    call = {
        
        accept = {
            L = 0,
            M = 0
        },
        reply = {
            sms = {
                enable  = 1,
                content = '%s，很抱歉无法及时处理您的来电，您可短信给我留言，我会尽快与您联系。这是一条自动回复短信'
            }
        }
    },
    sim = {},
    system = {
        power = {
            notify = 1,
            usb    = 1,
            reboot = 8
        },
        led = {
            network = {
                gpio = 30
            },
            event = {
                gpio  = 27,
                total = 5,
                wait  = 60
            }
        },
        ctrl = {
            '13800138000',
            '13912345678',
            '13700137000',
            '13601136011',
            '13500135000',
            '13400134000'
        }
    }
}