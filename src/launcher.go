// Copyright (c) 2026 Zhidao Assistant contributors.
// SPDX-License-Identifier: GPL-3.0-only
// Windows GUI launcher for the unchanged WPF client.
package main

import (
    "os"
    "os/exec"
    "path/filepath"
    "syscall"
    "unsafe"
)

var (
    user32 = syscall.NewLazyDLL("user32.dll")
    messageBox = user32.NewProc("MessageBoxW")
)

func alert(text, title string) {
    t, _ := syscall.UTF16PtrFromString(text)
    h, _ := syscall.UTF16PtrFromString(title)
    messageBox.Call(0, uintptr(unsafe.Pointer(t)), uintptr(unsafe.Pointer(h)), 0x10)
}

func main() {
    root := os.Getenv("LOCALAPPDATA")
    if root == "" {
        alert("找不到 Windows 用户本地程序目录。", "知到学习助手")
        return
    }
    script := filepath.Join(root, "ZHSDesktop", "Zhidao-GUI.ps1")
    if _, err := os.Stat(script); err != nil {
        alert("程序文件缺失，请重新运行安装程序。", "知到学习助手")
        return
    }
    cmd := exec.Command("powershell.exe", "-NoProfile", "-STA", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", script)
    cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
    if home, err := os.UserHomeDir(); err == nil { cmd.Dir = home }
    // WPF stays visible; only its PowerShell host console is hidden.
    if err := cmd.Run(); err != nil {
        alert("应用未能正常启动或运行。请在安装目录中用 PowerShell 检查 Zhidao-GUI.ps1。", "知到学习助手")
    }
}
