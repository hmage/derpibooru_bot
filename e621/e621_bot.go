package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"math/rand"
	"mime/multipart"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"

	// "github.com/bradfitz/gomemcache/memcache"
	rate "github.com/beefsack/go-rate"
	"github.com/bluele/gcache"
	"github.com/davecgh/go-spew/spew"
	"gopkg.in/yaml.v2"
)

type telegramBot struct {
	Token       string   `yaml:"telegram_token"`
	BlockedTags []string `yaml:"blocked_tags"`

	lastKnownUpdateID int64
}

type telegramResponse struct {
	OK          bool            `json:"ok"`
	Result      json.RawMessage `json:"result"`
	ErrorCode   int             `json:"error_code"`
	Description string          `json:"description"`
}

type telegramUpdate struct {
	// fields we're not interested in are not here
	ID          int64                `json:"update_id"`
	Message     *telegramMessage     `json:"message"`
	InlineQuery *telegramInlineQuery `json:"inline_query"`
}

type telegramMessage struct {
	// fields we're not interested in are not here
	ID   int64 `json:"message_id"`
	From *telegramUser
	Date telegramDate
	Chat telegramChat
	Text string
}

type telegramDate time.Time

type telegramInlineQuery struct {
	ID     string
	From   *telegramUser
	Query  string
	Offset string
}

type telegramInlineQueryResult struct {
	Type         string `json:"type"`
	ID           string `json:"id"`
	Photo_URL    string `json:"photo_url,omitempty"`
	Gif_URL      string `json:"gif_url,omitempty"`
	Gif_Width    int    `json:"gif_width,omitempty"`
	Gif_Height   int    `json:"gif_height,omitempty"`
	Thumb_URL    string `json:"thumb_url,omitempty"`
	Photo_Width  int    `json:"photo_width,omitempty"`
	Photo_Height int    `json:"photo_height,omitempty"`
	Title        string `json:"title,omitempty"`
	Description  string `json:"description,omitempty"`
	Caption      string `json:"caption,omitempty"`
}

type telegramUser struct {
	// fields we're not interested in are not here
	ID           int    `json:"id"`
	Bot          bool   `json:"is_bot"`
	FirstName    string `json:"first_name"`
	LastName     string `json:"last_name"`
	Username     string `json:"username"`
	LanguageCode string `json:"language_code"`
}

type telegramChat struct {
	// fields we're not interested in are not here
	ID          int64  `json:"id"`
	Type        string `json:"type"`
	Title       string `json:"title"`
	Username    string `json:"username"`
	FirstName   string `json:"first_name"`
	LastName    string `json:"last_name"`
	Description string `json:"description"`
}

// empty struct is ready to use
type mimeValues struct {
	writer *multipart.Writer
	bb     *bytes.Buffer
}

type e621Entry struct {
	// fields we're not interested in are not here
	ID int64

	Score struct {
		Up    int
		Down  int
		Total int
	}
	File struct {
		Ext    string
		Width  int
		Height int
		Url    string `json:"url"`
		Size   int64
	}
	Sample struct {
		Has    bool
		Width  int
		Height int
		Url    string
	}
	Preview struct {
		Width  int
		Height int
		Url    string
	}
}

var (
	bot   telegramBot
	cache = gcache.New(100).LRU().Expiration(cacheDuration * time.Second).Build()
	rl    = rate.New(maxRPS, time.Second)
)

const (
	userAgent     = "Derpibooru and E621 Telegram Bot/0.2 (http://github.com/hmage/derpibooru_bot)"
	helloMessage  = "Hello! I'm a bot that sends you images from e621.net.\n\nTo get a random top scoring picture: /yiff\n\nTo search for horsecock: /yiff horsecock\n\nYou get the idea :)"
	cacheDuration = 600 // in seconds
	maxRPS        = 1   // requests per second
)

var messageHandlers = map[string]func(telegramUpdate) error{
	"hello":     handleHello,
	"help":      handleHello,
	"start":     handleHello,
	"yiff":      handleYiff,
	"feral":     handleFeral,
	"horsecock": handleHorsecock,
}

func main() {
	rand.Seed(time.Now().UnixNano())
	err := readConfig("e621.yaml")
	if err != nil {
		panic(err)
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
			go func(update telegramUpdate) {
				// log each update
				logUpdate(update)

				if update.InlineQuery != nil {
					log.Printf("Got inline query: %s", spew.Sdump(update))
					err := inlineHandler(update)
					if err != nil {
						replyErrorAndLog(update, "Failed to handle inline query: %s", err)
						return
					}
				}

				if update.Message != nil {
					command := update.Message.Command()
					if command == "" {
						// log.Printf("Got a message without command: %s", spew.Sdump(update))
						return
					}
					log.Printf("got command from %s: %s", update.Message.From.Username, command)
					messageHandler, ok := messageHandlers[command]
					if !ok {
						log.Printf("Got unknown command %s", command)
						return
					}
					err := messageHandler(update)
					if err != nil {
						replyErrorAndLog(update, "Failed to handle command %s: %s", command, err)
						return
					}
				}

			}(update)
		}
	}
}

func readConfig(filename string) error {
	body, err := ioutil.ReadFile(filename)
	if err != nil {
		return err
	}

	err = yaml.Unmarshal(body, &bot)
	if err != nil {
		return err
	}

	if bot.Token == "" {
		return fmt.Errorf("Got an empty telegram token")
	}

	return nil
}

func logUpdate(update telegramUpdate) {
	if update.Message != nil {
		log.Printf("%#v", update.Message)
	}
	if update.InlineQuery != nil {
		log.Printf("%#v", update.InlineQuery)
	}
}

func (b *telegramBot) getUpdates() ([]telegramUpdate, error) {
	// trace("called")
	params := url.Values{}
	if b.lastKnownUpdateID != 0 {
		params.Add("offset", strconv.FormatInt(b.lastKnownUpdateID+1, 10))
	}
	params.Add("timeout", "20")
	url := fmt.Sprintf("https://api.telegram.org/bot%s/%s", b.Token, "getUpdates")
	resp, err := http.PostForm(url, params)
	if resp != nil && resp.Body != nil {
		defer resp.Body.Close()
	}
	if err != nil {
		return nil, err
	}

	response := &telegramResponse{}
	err = json.NewDecoder(resp.Body).Decode(response)
	if err != nil {
		return nil, err
	}

	if !response.OK {
		// spew.Dump(response)
		err := fmt.Errorf("Telegram said it's not OK: %d %s", response.ErrorCode, response.Description)
		return nil, err
	}

	var updates []telegramUpdate
	err = json.Unmarshal(response.Result, &updates)
	if err != nil {
		return nil, err
	}

	// update last known ID, otherwise server will send the same messages again and again
	// also, it might reset to random value after inactivity, do not assume it is always increasing between requests
	var largestID int64
	for _, update := range updates {
		if update.ID > largestID {
			largestID = update.ID
		}
	}

	b.lastKnownUpdateID = largestID

	return updates, nil
}

func (m *telegramMessage) Command() string {
	if m.Text == "" {
		return ""
	}
	if m.Text[0] != '/' {
		return ""
	}

	result := strings.Fields(m.Text)
	if len(result) == 0 {
		return ""
	}
	command := result[0]
	// remove the @ if it exists
	if i := strings.Index(command, "@"); i != -1 {
		command = command[:i]
	}
	command = command[1:]              // remove slash in the beginning
	command = strings.ToLower(command) // make it lowercase
	return command                     // remove slash in the beginning
}

func (m *telegramMessage) CommandOptions() string {
	if m.Text == "" {
		return ""
	}
	if m.Text[0] != '/' {
		return ""
	}

	result := strings.Fields(m.Text)
	if len(result) <= 1 {
		return ""
	}

	command := result[0]
	return m.Text[len(command)+1:]
}

//
// bot inline handler
//
func inlineHandler(update telegramUpdate) error {
	return nil
	/*
		limiter := "safe"
		search := update.InlineQuery.Query
		switch {
		case strings.Contains(search, "explicit"):
			limiter = "explicit"
		case strings.Contains(search, "suggestive"):
			limiter = "suggestive"
		}
		entries, err := getImages(search, limiter)
		if err != nil {
			return fmt.Errorf("Failed to get images with search %q: %w", search, err)
		}
		params := mimeValues{}
		params.Add("inline_query_id", update.InlineQuery.ID)
		results := []telegramInlineQueryResult{}
		for i, entry := range entries {
			if i >= 50 {
				// no more than 50 results per query are allowed
				break
			}
			photoURL, err := url.Parse(entry.Representations["tall"])
			if err != nil {
				return fmt.Errorf("Failed parsing photo URL: %w", err)
			}
			photoURL.Scheme = "https"
			thumbURL, err := url.Parse(entry.Representations["thumb"])
			if err != nil {
				return fmt.Errorf("Failed parsing thumb URL: %w", err)
			}
			thumbURL.Scheme = "https"
			result := telegramInlineQueryResult{
				ID:        strconv.FormatInt(entry.ID, 10),
				Thumb_URL: thumbURL.String(),
				Caption:   fmt.Sprintf("https://derpibooru.org/%d", entry.ID),
			}
			if strings.HasSuffix(entry.Representations["tall"], ".gif") {
				result.Type = "gif"
				result.Gif_URL = photoURL.String()
				result.Gif_Width = entry.Width
				result.Gif_Height = entry.Height
			} else {
				result.Type = "photo"
				result.Photo_URL = photoURL.String()
				result.Photo_Width = entry.Width
				result.Photo_Height = entry.Height
			}
			results = append(results, result)
		}
		resultsJSON, err := json.Marshal(results)
		if err != nil {
			return fmt.Errorf("Failed to marshal inline query results into JSON: %w", err)
		}
		params.Add("results", string(resultsJSON))
		params.Add("cache_time", 1)
		err = bot.sendInternal("answerInlineQuery", params, update)
		if err != nil {
			return fmt.Errorf("sendInternal failed: %w", err)
		}
	*/
	return nil
}

// --------------------
// bot command handlers
// --------------------
func handleHello(update telegramUpdate) error {
	return bot.sendMessage(update, helloMessage)
}

func handleYiff(update telegramUpdate) error {
	return handleImage(update, "", true)
}

func handleFeral(update telegramUpdate) error {
	return handleImage(update, "feral", true)
}

func handleHorsecock(update telegramUpdate) error {
	return handleImage(update, "horsecock", true)
}

func handleImage(update telegramUpdate, limiter string, forceRandom bool) error {
	trace("called")
	err := bot.sendChatAction(update, "upload_photo")
	if err != nil {
		return err
	}

	search := update.Message.CommandOptions()
	isRandom := forceRandom || search == "" // do we need to choose random entry from results?

	trace("getting images from e621")
	start := time.Now()
	entries, err := getImages(search, limiter)
	if err != nil {
		return err
	}
	gotImages := time.Now()

	trace("Got images from e621 in %s", gotImages.Sub(start))

	if len(entries) == 0 {
		err = bot.sendMessage(update, "I am sorry, "+update.Message.From.FirstName+", got no images to reply with.")
		if err != nil {
			return err
		}
		return nil
	}

	entry := entries[0]
	if isRandom {
		entry = entries[rand.Intn(len(entries))]
	}
	spew.Dump(entry)
	location := entry.File.Url
	// telegram API limits to 5 megabytes for photos (gif isn't a photo)
	if entry.File.Ext != "gif" {
		if entry.File.Size > 5*1024*1024 {
			if entry.Sample.Has { // have sample? use it
				location = entry.Sample.Url
			} else {
				location = entry.Preview.Url // don't have sample, use tiny preview
			}
		}
	}

	imageURL, err := url.Parse(location)
	if err != nil {
		return err
	}
	if imageURL.Scheme == "" {
		imageURL.Scheme = "https"
	}

	caption := fmt.Sprintf("https://e621.net/posts/%d", entry.ID)

	start = time.Now()
	if entry.File.Ext == "gif" {
		err = bot.sendDocument(update, imageURL, caption)
		if err != nil {
			return err
		}
	} else {
		err = bot.sendPhoto(update, imageURL, caption)
		if err != nil {
			return err
		}
	}

	elapsed := time.Since(start)
	trace("sending reply took %s", elapsed)

	return nil
}

func getImages(search, limiter string) ([]e621Entry, error) {
	url := url.URL{}
	url.Scheme = "https"
	url.Host = "e621.net"
	url.Path = "/posts.json"
	query := url.Query()

	tags := []string{}

	separated := strings.Split(search, " ")
	for _, tag := range separated {
		tag = strings.TrimSpace(tag)
		if tag == "" {
			continue
		}
		tags = append(tags, strings.ToLower(tag))
	}
	if limiter != "" {
		tags = append(tags, strings.ToLower(limiter))
	}

	// cache key must only use user input, so ignore rest
	sort.Strings(tags)
	cacheKey := strings.Join(tags, " ")

	// synthesize more query parameters based on settings

	// if search is empty, we need top scoring ones in last 3 days
	if search == "" {
		// it's an empty search, so choose best in last 3 days
		from := time.Now().Add(time.Hour * 24 * 3 * -1)
		tags = append(tags, "order:score date:>="+from.Format("2006-01-02"))
	}

	// we have our search query, set it and encode into URL
	query.Set("tags", strings.Join(tags, " "))
	query.Set("limit", "100")
	url.RawQuery = query.Encode()
	location := url.String()

	// fetch the URL, cache to avoid re-fetching if possible
	jsonBody, err := cachedGet(location, cacheKey)
	if err != nil {
		return nil, fmt.Errorf("Failed to get from URL %s: %w", location, err)
	}

	// parse json body
	root := map[string]*json.RawMessage{}
	err = json.Unmarshal(jsonBody, &root)
	if err != nil {
		return nil, err
	}

	// now get actual images json
	parent := "posts"
	entries := []e621Entry{}
	err = json.Unmarshal(*root[parent], &entries)
	if err != nil {
		return nil, err
	}

	// filter out problematic entries
	newentries := []e621Entry{}
	for _, entry := range entries {
		// remove webm and swf
		if entry.File.Ext == "webm" {
			continue
		}
		if entry.File.Ext == "swf" {
			continue
		}
		// remove entries with null urls
		if entry.File.Url == "" {
			continue
		}
		newentries = append(newentries, entry)
	}
	entries = newentries

	// sort by score
	sort.SliceStable(entries, func(i, j int) bool { return entries[i].Score.Total > entries[j].Score.Total })
	return entries, nil
}

// cache maps URL to []byte
func cachedGet(location string, cacheKey string) ([]byte, error) {
	// check cache
	{
		cached, err := cache.Get(cacheKey)
		switch err {
		case nil:
			// found, return the data
			cached, ok := cached.([]byte)
			if ok {
				trace("Found key %s in cache: %d bytes", cacheKey, len(cached))
				return cached, nil
			}
			log.Printf("SHOULD NOT HAPPEN -- fetched data from cache for key \"%s\" is not []byte!", cacheKey)
		case gcache.KeyNotFoundError:
			// do nothing, not found
		default:
			// log but continue working, cache might be down
			log.Printf("Couldn't fetch data from cache for key \"%s\": %s", cacheKey, err)
		}
	}

	// ratelimit if neccessary
	rl.Wait()
	// fetch from network
	// trace("doing GET %s", location)
	req, err := http.NewRequest("GET", location, nil)
	if err != nil {
		return nil, fmt.Errorf("Failed to prepare a request for url %q: %s", location, err)
	}
	req.Header.Set("User-Agent", userAgent)
	resp, err := http.DefaultClient.Do(req)
	if resp != nil && resp.Body != nil {
		defer resp.Body.Close()
	}
	if err != nil {
		return nil, fmt.Errorf("Couldn't fetch url \"%s\": %s", location, err)
	}
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("Couldn't read body of url \"%s\": %s", location, err)
	}
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("Unexpected status code %d from url \"%s\"", resp.StatusCode, location)
	}

	if !isJSON(body) {
		return nil, fmt.Errorf("Body of url \"%s\" is not a JSON", location)
	}

	// save cache
	// trace("Saving '%s' into cache: %d bytes", cacheKey, len(body))
	err = cache.Set(cacheKey, body)
	if err != nil {
		log.Printf("Couldn't set cache data for key \"%s\": %s", cacheKey, err)
		// don't fail, it's a temporary error and next time it might be fine
	}

	return body, nil
}

func isJSON(s []byte) bool {
	var js interface{}
	return json.Unmarshal(s, &js) == nil
}

//
// helper functions
//
func replyErrorAndLog(update telegramUpdate, format string, args ...interface{}) {
	text := fmt.Sprintf(format, args...)
	err := log.Output(2, text)
	if err != nil {
		panic(err)
	}
	// don't send to telegram if message is nil
	if update.Message != nil {
		return
	}
	message := fmt.Sprintf("Apologies, got error:\n\n%s\n\nGo pester @hmage to fix this.", text)
	err = bot.sendMessage(update, message)
	if err != nil {
		trace("bot.Send() returned %+v", err)
		return
	}
}

//
// telegram sending
//
func (b *telegramBot) sendMessage(update telegramUpdate, message string) error {
	params := mimeValues{}
	err := params.Add("text", message)
	if err != nil {
		return err
	}

	return b.sendInternal("sendMessage", params, update)
}

func (b *telegramBot) sendChatAction(update telegramUpdate, action string) error {
	params := mimeValues{}
	err := params.Add("action", action)
	if err != nil {
		return err
	}

	return b.sendInternal("sendChatAction", params, update)
}

func (b *telegramBot) sendPhoto(update telegramUpdate, photoURL *url.URL, caption string) error {
	trace("called with photo %s", photoURL)
	params := mimeValues{}
	err := params.Add("photo", photoURL.String())
	if err != nil {
		return fmt.Errorf("Failed to add parameter: %w", err)
	}
	err = params.Add("caption", caption)
	if err != nil {
		return fmt.Errorf("Failed to add parameter: %w", err)
	}

	return b.sendInternal("sendPhoto", params, update)
}

func (b *telegramBot) sendDocument(update telegramUpdate, documentURL *url.URL, caption string) error {
	trace("called with document %s", documentURL)
	params := mimeValues{}
	err := params.Add("document", documentURL.String())
	if err != nil {
		return fmt.Errorf("Failed to add parameter: %w", err)
	}
	err = params.Add("caption", caption)
	if err != nil {
		return fmt.Errorf("Failed to add parameter: %w", err)
	}

	return b.sendInternal("sendDocument", params, update)
}

func (b *telegramBot) sendInternal(method string, params mimeValues, update telegramUpdate) error {
	// trace("called")
	if params.writer == nil {
		return fmt.Errorf("sendInternal() was called with nil mime params writer")
	}
	if params.bb == nil {
		return fmt.Errorf("sendInternal() was called with nil mime params bytes buffer")
	}

	if update.Message != nil {
		err := params.Add("chat_id", update.Message.Chat.ID)
		if err != nil {
			return fmt.Errorf("Failed to set chat_id to mime params: %w", err)
		}

		err = params.Add("reply_to_message_id", update.Message.ID)
		if err != nil {
			return fmt.Errorf("Failed to set reply_to_message_id to mime params: %w", err)
		}
	}

	err := params.writer.Close()
	if err != nil {
		return err
	}

	url := fmt.Sprintf("https://api.telegram.org/bot%s/%s", b.Token, method)
	// trace("url is %s", url)
	req, err := http.NewRequest("POST", url, params.bb)
	if err != nil {
		return err
	}

	contentType := params.writer.FormDataContentType()
	req.Header.Set("Content-Type", contentType)
	req.Header.Set("User-Agent", userAgent)

	// trace("contentType is %s", contentType)
	// trace("req is %s", spew.Sdump(req))
	resp, err := http.DefaultClient.Do(req)
	if resp != nil && resp.Body != nil {
		defer resp.Body.Close()
	}
	if err != nil {
		return err
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	if resp.StatusCode != 200 {
		trace("response from telegram for method %s: status %s, body %s", method, resp.Status, body)
		return fmt.Errorf("Unexpected status code from Telegram API: %s", resp.Status)
	}

	data := map[string]interface{}{}
	err = json.Unmarshal(body, &data)
	if err != nil {
		return err
	}
	if data["ok"] != true {
		return fmt.Errorf("Telegram API returned !ok: %s", data["description"])
	}

	return nil
}

func (m *mimeValues) Add(key string, value interface{}) error {
	if m.bb == nil {
		m.bb = &bytes.Buffer{}
	}
	if m.writer == nil {
		m.writer = multipart.NewWriter(m.bb)
	}
	writer, err := m.writer.CreateFormField(key)
	if err != nil {
		return err
	}

	switch v := value.(type) {
	case string:
		_, err = io.Copy(writer, strings.NewReader(v))
		if err != nil {
			return err
		}
	case int:
		_, err = io.Copy(writer, strings.NewReader(strconv.Itoa(v)))
		if err != nil {
			return err
		}
	case int64:
		_, err = io.Copy(writer, strings.NewReader(strconv.FormatInt(v, 10)))
		if err != nil {
			return err
		}
	case []byte:
		_, err = io.Copy(writer, bytes.NewReader(v))
		if err != nil {
			return err
		}
	default:
		log.Panicf("Unknown value type %T for key %s", v, key)
	}

	if x, ok := writer.(io.Closer); ok {
		defer x.Close()
	}
	return nil
}

func (t *telegramDate) UnmarshalJSON(b []byte) error {
	var value int64
	err := json.Unmarshal(b, &value)
	if err != nil {
		log.Printf("Couldn't unmarshal telegram date: %s", err)
		return err
	}
	*(*time.Time)(t) = time.Unix(value, 0)
	return nil
}

func (t *telegramDate) String() string {
	return (*time.Time)(t).String()
}
