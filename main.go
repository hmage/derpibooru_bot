package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"math/rand"
	"net/http"
	"net/url"
	"sort"

	"time"

	"github.com/davecgh/go-spew/spew"
	"gopkg.in/yaml.v2"
)

var bot telegramBot

type configuration struct {
	TelegramToken string   `yaml:"telegram_token_test"`
	DerpibooruKey string   `yaml:"derpibooru_key"`
	BlockedTags   []string `yaml:"blocked_tags"`
}

var config configuration

func main() {
	err := readConfig(&bot, "settings.yaml")
	if err != nil {
		log.Panic(err)
	}
	for {
		updates, err := bot.getUpdates()
		if err != nil {
			log.Printf("Got an error when getting updates: %s", err)
			log.Printf("Failed to get updates, will retry in one second")
			time.Sleep(time.Second)
			continue
		}
		if len(updates) == 0 {
			// nothing to do, move on
			continue
		}
		for _, update := range updates {
			// handle the update
			spew.Dump(update)
			var ChatID int64
			var err error
			if update.Message != nil {
				ChatID = update.Message.Chat.ID
				log.Printf("command is %s", update.Message.Command())
				// handle the message
				switch update.Message.Command() {
				case "hello":
					err = handleHello(update)
				case "start":
					err = handleStart(update)
				case "pony":
					err = handlePony(update)
				case "randpony":
					err = handleRandPony(update)
				case "clop":
					err = handleClop(update)
				case "randclop":
					err = handleRandClop(update)
				}
			}

			if err != nil {
				replyErrorAndLog(ChatID, "%s", err)
				continue
			}

		}
	}
}

func readConfig(b *telegramBot, filename string) error {
	body, err := ioutil.ReadFile(filename)
	if err != nil {
		return err
	}

	err = yaml.Unmarshal(body, &config)
	if err != nil {
		return err
	}

	b.Token = config.TelegramToken
	if b.Token == "" {
		return fmt.Errorf("Got an empty telegram token")
	}

	return nil
}

// ------------------
// Telegram callbacks
// ------------------
func handleHello(update telegramUpdate) error {
	message := "Hello! I'm a bot by @hmage that sends ponies from derpibooru.org.\n\nTo get a random top scoring picture: /pony\n\nTo get best recent picture with Celestia: /pony Celestia\n\nTo get random recent picture with Celestia: /randpony Celestia\n\nYou get the idea :)"
	err := bot.sendMessage(update.Message.Chat.ID, message)
	if err != nil {
		return err
	}
	return nil
}

func handleStart(update telegramUpdate) error {
	return handleHello(update)
}

// ------------
// image search
// ------------

func handlePony(update telegramUpdate) error {
	return handleImage(update, "safe", false)
}

func handleRandPony(update telegramUpdate) error {
	return handleImage(update, "safe", true)
}

func handleClop(update telegramUpdate) error {
	return handleImage(update, "explicit", false)
}

func handleRandClop(update telegramUpdate) error {
	return handleImage(update, "explicit", true)
}

func handleImage(update telegramUpdate, limiter string, forceRandom bool) error {
	err := bot.sendChatAction(update.Message.Chat.ID, "upload_photo")
	if err != nil {
		return err
	}

	search := update.Message.CommandOptions()
	isRandom := forceRandom || search == ""

	entries, err := getImages(search, limiter)
	if err != nil {
		return err
	}
	if len(entries) == 0 {
		err = bot.sendMessage(update.Message.Chat.ID, "I am sorry, "+update.Message.From.FirstName+", got no images to reply with.")
		if err != nil {
			return err
		}
		return nil
	}

	var caption string
	switch {
	case search == "" && !isRandom: // if search is empty, it forces random
		caption = "Random top scoring image in last 3 days"
	case search == "" && isRandom: // if search is empty, it forces random
		caption = "Random top scoring image in last 3 days"
	case search == "" && !isRandom:
		caption = "Best recent image for your search"
	case search == "" && isRandom:
		caption = "Random recent image for your search"
	}

	entry := entries[0]
	if isRandom {
		entry = entries[rand.Intn(len(entries))]
	}
	image, err := fetchImage(&entry)
	if err != nil {
		return err
	}

	caption = fmt.Sprintf("https://derpibooru.org/%d\n%s", entry.ID, caption)
	filename := fmt.Sprintf("%d.%s", entry.ID, entry.Original_format)
	if entry.Original_format == "gif" {
		err = bot.sendDocument(update.Message.Chat.ID, image, filename, caption)
	} else {
		err = bot.sendPhoto(update.Message.Chat.ID, image, filename, caption)
	}
	if err != nil {
		return err
	}

	return nil
}

func getImages(search, limiter string) ([]derpiEntry, error) {
	url := url.URL{}
	url.Scheme = "https"
	url.Host = "derpibooru.org"
	url.Path = "/search.json"
	query := url.Query()

	if search == "" {
		// empty search, choose best in last 3 days
		from := time.Now().Add(time.Hour * 24 * 3 * -1)
		search = "created_at.gt:" + from.Format(time.RFC3339)
		query.Set("sf", "score")
		query.Set("sd", "desc")
	}

	// if derpibooru key is set, use it
	if config.DerpibooruKey != "" {
		query.Set("key", config.DerpibooruKey)
	}

	// enforce limiter
	search = search + ", " + limiter

	// enforce blocked tags
	for _, tag := range config.BlockedTags {
		search = search + ", -" + tag
	}

	query.Set("q", search)
	url.RawQuery = query.Encode()

	trace("Fetching '%s'", url.String())
	resp, err := http.Get(url.String())
	spew.Dump(resp, err)
	if err != nil {
		return nil, err
	}
	if resp != nil && resp.Body != nil {
		defer resp.Body.Close()
	}
	jsonBody, err := ioutil.ReadAll(resp.Body)

	// parse json body
	root := map[string]*json.RawMessage{}
	err = json.Unmarshal(jsonBody, &root)
	if err != nil {
		return nil, err
	}

	// now get actual images json
	entries := []derpiEntry{}
	parent := "search"
	err = json.Unmarshal(*root[parent], &entries)
	if err != nil {
		return nil, err
	}

	// sort by score
	sort.SliceStable(entries, func(i, j int) bool { return entries[i].Score > entries[j].Score })

	return entries, nil
}

func fetchImage(entry *derpiEntry) ([]byte, error) {
	url, err := url.Parse(entry.Representations["tall"])
	if err != nil {
		return nil, err
	}
	if url.Scheme == "" {
		url.Scheme = "https"
	}
	resp, err := http.Get(url.String())
	if resp != nil && resp.Body != nil {
		defer resp.Body.Close()
	}
	if err != nil {
		return nil, err
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	return body, nil
}

//
// helper functions
//
func replyErrorAndLog(chatID int64, format string, args ...interface{}) {
	text := fmt.Sprintf(format, args...)
	log.Printf(text)
	// don't send to telegram if chatID is 0
	if chatID == 0 {
		return
	}
	message := fmt.Sprintf("Apologies, got error:\n\n%s\n\nGo pester @hmage to fix this.", text)
	err := bot.sendMessage(chatID, message)
	if err != nil {
		trace("bot.Send() returned %+v", err)
		return
	}
}
