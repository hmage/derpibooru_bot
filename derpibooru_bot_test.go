package main

import (
	"os"
	"sync"
	"testing"
)

func TestDerpibooru(t *testing.T) {
	entries, err := getImages("", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 48 {
		t.Fatalf("expected 50 entries, got %d", len(entries))
	}
}

func BenchmarkDerpibooru(b *testing.B) {
	limit := make(chan bool, 8000)
	wg := sync.WaitGroup{}
	for i := 0; i < b.N; i++ {
		limit <- true
		wg.Add(1)
		go func() {
			entries, err := getImages("", "")
			if err != nil {
				b.Fatal(err)
			}
			if len(entries) != 50 {
				b.Fatalf("expected 50 entries, got %d", len(entries))
			}
			<-limit
			wg.Done()
		}()
	}
	wg.Wait()
}

func TestMain(m *testing.M) {
	err := readConfig("settings.yaml")
	if err != nil {
		panic(err)
	}
	os.Exit(m.Run())
}
