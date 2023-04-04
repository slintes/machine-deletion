package utils

import (
	"fmt"
	"strings"

	"github.com/go-logr/logr"
)

type TestLogger struct {
	Output []string
	R      logr.RuntimeInfo
}

func (t *TestLogger) doLog(level int, msg string, keysAndValues ...interface{}) {
	s := make([]string, len(keysAndValues)+1)
	s[0] = msg
	for i, v := range keysAndValues {
		s[i+1] = fmt.Sprint(v)
	}
	t.Output = append(t.Output, strings.Join(s[:], " "))
}
func (t *TestLogger) Init(info logr.RuntimeInfo) { t.R = info }
func (t *TestLogger) Enabled(level int) bool     { return true }
func (t *TestLogger) Info(level int, msg string, keysAndValues ...interface{}) {
	t.doLog(level, msg, keysAndValues...)
}
func (t *TestLogger) Error(err error, msg string, keysAndValues ...interface{}) {
	t.doLog(0, "cust: "+msg, append(keysAndValues, err)...)
}
func (t *TestLogger) WithValues(keysAndValues ...interface{}) logr.LogSink { return t }
func (t *TestLogger) WithName(name string) logr.LogSink                    { return t }

//func TestLoggerHasOutput(t *testing.T) {

//l := &TestLogger{make(map[string]map[int][]interface[]), RuntimeInfo{1}}
//tl := logr.New(l)
//config, err := GetConfig(kcfgFilePath, "ns", tl, "test")
//assert.Contains(t, l.Output, "ns") // you can also test the contents of the output as well
//}
