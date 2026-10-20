package main

import (
	"os"

	"golang.org/x/sys/windows"
)




func singleInstance() bool {
	h, err := windows.CreateMutex(nil, false, windows.StringToUTF16Ptr("Global\\SmsNotifySingleInstance"))
	if err == windows.ERROR_ALREADY_EXISTS {
		return false
	}
	_ = h 
	return true
}

func guardSingleInstance() {
	if !singleInstance() {
		logf("已有实例在运行，本进程退出")
		showToast(appName, "通知程序已在运行")
		os.Exit(0)
	}
}
