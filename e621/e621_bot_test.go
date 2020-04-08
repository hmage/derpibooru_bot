package main

import (
	"os"
	"testing"
)

func TestDerpibooru(t *testing.T) {
	entries, err := getImages("", "")
	if err != nil {
		t.Fatal(err)
	}
	expected := 100
	if len(entries) != expected {
		t.Fatalf("expected %d entries, got %d", expected, len(entries))
	}
}

func TestMain(m *testing.M) {
	err := readConfig("e621.yaml")
	if err != nil {
		panic(err)
	}
	os.Exit(m.Run())
}
