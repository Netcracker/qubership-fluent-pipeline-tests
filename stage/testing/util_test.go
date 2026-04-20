package testing

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	loggingService "github.com/Netcracker/qubership-logging-operator/api/v1"
)

type stubAgent struct {
	outputFileName string
}

func (s stubAgent) UpdateCustomConfiguration(data map[string]string, _ *loggingService.LoggingService) map[string]string {
	return data
}

func (s stubAgent) GetOutputFileName() string {
	return s.outputFileName
}

func TestIgnoreFluentdTimeFunc(t *testing.T) {
	t.Parallel()

	modify := ignoreFluentdTimeFunc("audit.log.json")

	// File is in the ignore list: fluentd_time in expected should be overwritten with the actual value.
	expected := map[string]interface{}{"fluentd_time": "expected"}
	actual := map[string]interface{}{"fluentd_time": "actual"}
	if err := modify(expected, actual, "audit.log.json"); err != nil {
		t.Fatalf("ignoreFluentdTimeFunc returned error: %v", err)
	}
	if expected["fluentd_time"] != "actual" {
		t.Fatalf("fluentd_time = %v, want %v", expected["fluentd_time"], "actual")
	}

	// File is NOT in the ignore list: expected should remain unchanged.
	expected2 := map[string]interface{}{"fluentd_time": "expected"}
	actual2 := map[string]interface{}{"fluentd_time": "actual"}
	if err := modify(expected2, actual2, "other.log.json"); err != nil {
		t.Fatalf("ignoreFluentdTimeFunc returned error: %v", err)
	}
	if expected2["fluentd_time"] != "expected" {
		t.Fatalf("fluentd_time should not be changed for non-ignored file, got %v", expected2["fluentd_time"])
	}
}

func TestGetModificationFuncs(t *testing.T) {
	t.Parallel()

	if got := GetModificationFuncs("fluentd", "audit.log.json"); len(got) != 1 {
		t.Fatalf("GetModificationFuncs(fluentd) len = %d, want 1", len(got))
	}
	if got := GetModificationFuncs("fluentbit", "audit.log.json"); len(got) != 0 {
		t.Fatalf("GetModificationFuncs(fluentbit) len = %d, want 0", len(got))
	}
}

func TestApplyModificationFuncsStopsOnError(t *testing.T) {
	wantErr := errors.New("boom")
	calls := 0
	err := applyModificationFuncs(
		map[string]interface{}{},
		map[string]interface{}{},
		"file.log.json",
		[]RecordModifyFunc{
			func(expected, actual map[string]interface{}, file string) error {
				calls++
				return wantErr
			},
			func(expected, actual map[string]interface{}, file string) error {
				calls++
				return nil
			},
		},
	)
	if !errors.Is(err, wantErr) {
		t.Fatalf("applyModificationFuncs error = %v, want %v", err, wantErr)
	}
	if calls != 1 {
		t.Fatalf("applyModificationFuncs calls = %d, want 1", calls)
	}
}

func TestContains(t *testing.T) {
	if !contains([]string{"a", "b"}, "b") {
		t.Fatal("contains returned false for existing element")
	}
	if contains([]string{"a", "b"}, "c") {
		t.Fatal("contains returned true for missing element")
	}
}

// TestTestJSONSuccess cannot run in parallel: testJson resolves paths relative to
// the working directory, so os.Chdir is required and must not race with other tests.
func TestTestJSONSuccess(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "output-logs", "actual", "output.log"), "{\"logId\":\"1\",\"message\":\"ok\"}")
	writeFile(t, filepath.Join(dir, "output-logs", "expected", "sample.log.json"), "[{\"logId\":\"1\",\"message\":\"ok\"}]")

	oldWD, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	if err := os.Chdir(dir); err != nil {
		t.Fatalf("chdir temp dir: %v", err)
	}
	t.Cleanup(func() { _ = os.Chdir(oldWD) })

	success, err := testJson("", stubAgent{outputFileName: "output.log"}, nil)
	if err != nil {
		t.Fatalf("testJson returned error: %v", err)
	}
	if !success {
		t.Fatal("testJson success = false, want true")
	}
}

// TestTestJSONDuplicateLogIDFails cannot run in parallel: same reason as TestTestJSONSuccess.
func TestTestJSONDuplicateLogIDFails(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "output-logs", "actual", "output.log"), "{\"logId\":\"1\",\"message\":\"ok\"}\n{\"logId\":\"1\",\"message\":\"ok\"}")
	writeFile(t, filepath.Join(dir, "output-logs", "expected", "sample.log.json"), "[{\"logId\":\"1\",\"message\":\"ok\"}]")

	oldWD, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	if err := os.Chdir(dir); err != nil {
		t.Fatalf("chdir temp dir: %v", err)
	}
	t.Cleanup(func() { _ = os.Chdir(oldWD) })

	success, err := testJson("", stubAgent{outputFileName: "output.log"}, nil)
	if err != nil {
		t.Fatalf("testJson returned error: %v", err)
	}
	if success {
		t.Fatal("testJson success = true, want false")
	}
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()

	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", filepath.Dir(path), err)
	}
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}
