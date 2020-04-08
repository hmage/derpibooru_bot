package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

func trace(format string, args ...interface{}) {
	pc := make([]uintptr, 10) // at least 1 entry needed
	runtime.Callers(2, pc)
	f := runtime.FuncForPC(pc[0])
	var buf strings.Builder
	buf.WriteString(fmt.Sprintf("%s(): ", filepath.Base(f.Name())))
	text := fmt.Sprintf(format, args...)
	buf.WriteString(text)
	if len(text) == 0 || text[len(text)-1] != '\n' {
		buf.WriteRune('\n')
	}
	fmt.Fprint(os.Stderr, buf.String())
}
