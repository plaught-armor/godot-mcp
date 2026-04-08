//go:build windows

package main

import (
	"os"
	"syscall"
	"unsafe"
)

var (
	modkernel32     = syscall.NewLazyDLL("kernel32.dll")
	procLockFileEx  = modkernel32.NewProc("LockFileEx")
	procUnlockFileEx = modkernel32.NewProc("UnlockFileEx")
)

const (
	lockfileExclusiveLock   = 0x00000002
	lockfileFailImmediately = 0x00000001
)

func flockExclusive(f *os.File) error {
	return winLock(f, lockfileExclusiveLock)
}

func flockExclusiveNB(f *os.File) error {
	return winLock(f, lockfileExclusiveLock|lockfileFailImmediately)
}

func flockUnlock(f *os.File) {
	var ol syscall.Overlapped
	h := syscall.Handle(f.Fd())
	procUnlockFileEx.Call(uintptr(h), 0, 1, 0, uintptr(unsafe.Pointer(&ol)))
}

func daemonSysProcAttr() *syscall.SysProcAttr {
	return &syscall.SysProcAttr{CreationFlags: 0x00000008} // DETACHED_PROCESS
}

func winLock(f *os.File, flags uint32) error {
	var ol syscall.Overlapped
	h := syscall.Handle(f.Fd())
	r1, _, err := procLockFileEx.Call(uintptr(h), uintptr(flags), 0, 1, 0, uintptr(unsafe.Pointer(&ol)))
	if r1 == 0 {
		return err
	}
	return nil
}
