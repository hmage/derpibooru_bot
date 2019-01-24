package main

import (
	"encoding/json"
	"log"
	"strings"
	"time"
)

type derpiTags []string

type derpiEntry struct {
	ID               int64
	Created_at       time.Time
	Updated_at       time.Time
	First_seen_at    time.Time
	Score            int64
	Comment_count    int64
	Width            int64
	Height           int64
	File_name        string
	Description      string
	Uploader         string
	Uploader_id      int64
	Image            string
	Upvotes          int64
	Downvotes        int64
	Faves            int64
	Tags             derpiTags
	Tag_ids          []int64
	Aspect_ratio     float64
	Original_format  string
	Mime_type        string
	SHA512_hash      string
	Orig_SHA512_hash string
	Source_url       string
	Representations  map[string]string
	Is_rendered      bool
	Is_optimized     bool
}

func (t *derpiTags) UnmarshalJSON(b []byte) error {
	var str string
	err := json.Unmarshal(b, &str)
	if err != nil {
		log.Printf("Couldn't unmarshal Tags: %s", err)
		return err
	}
	tags := strings.Split(str, ", ")
	*t = derpiTags(tags)
	return nil
}
