package main

import (
	"golang.org/x/sys/windows/registry"
)



func registerAppID() {
	k, _, err := registry.CreateKey(
		registry.CURRENT_USER,
		`Software\Classes\AppUserModelId\`+appID,
		registry.SET_VALUE,
	)
	if err != nil {
		logf("AppID 注册失败(可忽略): %v", err)
		return
	}
	defer k.Close()
	_ = k.SetStringValue("DisplayName", appName)
}
