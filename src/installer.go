// Copyright (c) 2026 Zhidao Assistant contributors.
// SPDX-License-Identifier: GPL-3.0-only
// Windows x64 setup executable, embedding WPF launcher and dual-mode Python adapter.
package main

import (
    "archive/zip"
    "bytes"
    _ "embed"
    "errors"
    "fmt"
    "io"
    "os"
    "os/exec"
    "path/filepath"
    "runtime"
    "strings"
)

//go:embed payload.zip
var payload []byte

func unpackInto(dest string) error {
    r, err := zip.NewReader(bytes.NewReader(payload), int64(len(payload)))
    if err != nil { return err }
    for _, z := range r.File {
        clean := filepath.Clean(z.Name)
        if z.FileInfo().IsDir() { continue }
        if filepath.IsAbs(clean) || clean == ".." || strings.HasPrefix(clean, ".."+string(os.PathSeparator)) || strings.Contains(clean, ":") {
            return fmt.Errorf("非法安装资源路径: %s", z.Name)
        }
        target := filepath.Join(dest, clean)
        if err := os.MkdirAll(filepath.Dir(target), 0700); err != nil { return err }
        in, err := z.Open(); if err != nil { return err }
        out, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
        if err != nil { in.Close(); return err }
        _, copyErr := io.Copy(out, in)
        closeErr := out.Close()
        in.Close()
        if copyErr != nil { return copyErr }
        if closeErr != nil { return closeErr }
    }
    return nil
}

func install() error {
    if runtime.GOOS != "windows" { return errors.New("安装程序只能在 Windows 运行") }
    tempRoot, err := os.MkdirTemp("", "zhidao-setup-*")
    if err != nil { return err }
    defer os.RemoveAll(tempRoot)
    if err := unpackInto(tempRoot); err != nil { return err }
    script := filepath.Join(tempRoot, "Install.ps1")
    fmt.Println("正在安装知到学习助手 V5.2.9 Beta 1（仅知到 App）")
    fmt.Println("将安装到当前 Windows 用户目录，无需管理员权限。")
    fmt.Println("首次安装需要联网下载运行环境和 ZHS 0.1.5；每一步的下载日志会在窗口显示。")
    fmt.Println("如果下载进度长期为零，记录停留的 [1/4]-[4/4] 阶段和网络错误。")
    fmt.Println()
    cmd := exec.Command("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script)
    cmd.Dir = tempRoot
    cmd.Stdout, cmd.Stderr, cmd.Stdin = os.Stdout, os.Stderr, os.Stdin
    if err := cmd.Run(); err != nil { return fmt.Errorf("安装失败: %w", err) }
    return nil
}

func main() {
    exitCode := 0
    if err := install(); err != nil {
        fmt.Fprintln(os.Stderr, "\n错误:", err)
        fmt.Fprintln(os.Stderr, "安装未完成。应用文件复制阶段有回滚保护，但新依赖环境可能保留；个人 .zhs 数据不会主动清除。")
        exitCode = 1
    } else {
        fmt.Println("\n✓ 安装文件复制与依赖步骤已完成！Windows 播放和真实课程仍需验收。")
        fmt.Println("可通过桌面图标启动知到学习助手。")
    }
    fmt.Println("\n按回车关闭窗口。")
    var input string
    fmt.Scanln(&input)
    os.Exit(exitCode)
}
