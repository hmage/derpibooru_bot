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
	Token         string   `yaml:"telegram_token"`
	DerpibooruKey string   `yaml:"derpibooru_key"`
	BlockedTags   []string `yaml:"blocked_tags"`

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

type derpiEntry struct {
	// fields we're not interested in are not here
	ID              int64
	Width           int
	Height          int
	Original_format string
	Score           int64
	Representations map[string]string
}

var (
	bot   telegramBot
	cache = gcache.New(100).LRU().Expiration(cacheDuration * time.Second).Build()
	rl    = rate.New(maxRPS, time.Second)
)

const (
	helloMessage  = "Hello! I'm a bot by @hmage that sends ponies from derpibooru.org.\n\nTo get a random top scoring picture: /pony\n\nTo get best recent picture with Celestia: /pony Celestia\n\nTo get random recent picture with Celestia: /randpony Celestia\n\nYou get the idea :)"
	cacheDuration = 600 // in seconds
	maxRPS        = 10  // requests per second
)

var messageHandlers = map[string]func(telegramUpdate) error{
	"hello":    handleHello,
	"help":     handleHello,
	"start":    handleHello,
	"pony":     handlePony,
	"randpony": handleRandPony,
	"clop":     handleClop,
	"randclop": handleRandClop,
}

func main() {
	rand.Seed(time.Now().UnixNano())
	err := readConfig("settings.yaml")
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
		return nil
	}

	err = yaml.Unmarshal(body, &bot)
	if err != nil {
		return err
	}

	if bot.Token == "" {
		return fmt.Errorf("Got an empty telegram token")
	}

	if bot.DerpibooruKey == "" {
		return fmt.Errorf("Got an empty derpibooru key")
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
	return nil
}

// --------------------
// bot command handlers
// --------------------
func handleHello(update telegramUpdate) error {
	return bot.sendMessage(update, helloMessage)
}

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
	// trace("called")
	err := bot.sendChatAction(update, "upload_photo")
	if err != nil {
		return err
	}

	search := update.Message.CommandOptions()
	isRandom := forceRandom || search == ""

	// trace("getting images from derpibooru")
	start := time.Now()
	entries, err := getImages(search, limiter)
	if err != nil {
		return err
	}
	gotImages := time.Now()
	trace("Got images from derpibooru in %s", gotImages.Sub(start))
	if len(entries) == 0 {
		err = bot.sendMessage(update, "I am sorry, "+update.Message.From.FirstName+", got no images to reply with.")
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
	case search != "" && !isRandom:
		caption = "Best recent image for your search"
	case search != "" && isRandom:
		caption = "Random recent image for your search"
	}

	entry := entries[0]
	if isRandom {
		entry = entries[rand.Intn(len(entries))]
	}
	imageURL, err := url.Parse(entry.Representations["tall"])
	if err != nil {
		return err
	}
	if imageURL.Scheme == "" {
		imageURL.Scheme = "https"
	}

	caption = fmt.Sprintf("https://derpibooru.org/%d\n%s", entry.ID, caption)
	filename := fmt.Sprintf("%d.%s", entry.ID, entry.Original_format)

	start = time.Now()
	// If we have an mp4 representation, use it instead
	if v, ok := entry.Representations["mp4"]; ok {
		mp4URL, err := url.Parse(v)
		if err != nil {
			return err
		}
		err = bot.sendAnimation(update, mp4URL, filename, caption)
		if err != nil {
			return err
		}
	}
	if entry.Original_format == "gif" {
		err = bot.sendDocument(update, imageURL, filename, caption)
		if err != nil {
			return err
		}
	} else {
		err = bot.sendPhoto(update, imageURL, filename, caption)
		if err != nil {
			return err
		}
	}
	elapsed := time.Since(start)
	trace("sending reply took %s", elapsed)

	return nil
}

func getImages(search, limiter string) ([]derpiEntry, error) {
	url := url.URL{}
	url.Scheme = "https"
	url.Host = "derpibooru.org"
	url.Path = "/api/v1/json/search/images"
	query := url.Query()

	q := []string{}

	// if derpibooru key is set, use it
	if bot.DerpibooruKey != "" {
		query.Set("key", bot.DerpibooruKey)
	}

	tags := strings.Split(search, ",")
	for _, tag := range tags {
		tag = strings.TrimSpace(tag)
		if tag == "" {
			continue
		}
		q = append(q, strings.ToLower(tag))
	}

	// enforce limiter
	if limiter == "" {
		limiter = "safe"
	}
	q = append(q, strings.ToLower(limiter))

	// cache key must only use user input, so ignore rest
	sort.Strings(q)
	cacheKey := strings.Join(q, ", ")

	// synthesize more query parameters based on settings
	// enforce blocked tags
	for _, tag := range bot.BlockedTags {
		q = append(q, "-"+tag)
	}

	// if search is empty, we need top scoring ones in last 3 days
	if search == "" {
		// empty search, choose best in last 3 days
		from := time.Now().Add(time.Hour * 24 * 3 * -1)
		q = append(q, "created_at.gt:"+from.Format(time.RFC3339))
		query.Set("sf", "score")
		query.Set("sd", "desc")
	}

	// we have our search query, set it and encode into URL
	sort.Strings(q)
	query.Set("q", strings.Join(q, ", "))
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
	entries := []derpiEntry{}
	parent := "images"
	err = json.Unmarshal(*root[parent], &entries)
	if err != nil {
		return nil, err
	}

	// sort by score
	sort.SliceStable(entries, func(i, j int) bool { return entries[i].Score > entries[j].Score })

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
				// trace("Found key %s in cache: %d bytes", cacheKey, len(cached))
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
	resp, err := http.Get(location)
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
	// trace("Saving %s into cache: %d bytes", cacheKey, len(body))
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
		// trace("bot.Send() returned %+v", err)
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

func (b *telegramBot) sendPhoto(update telegramUpdate, photoURL *url.URL, filename string, caption string) error {
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

func (b *telegramBot) sendDocument(update telegramUpdate, documentURL *url.URL, filename string, caption string) error {
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

func (b *telegramBot) sendAnimation(update telegramUpdate, animationURL *url.URL, filename string, caption string) error {
	params := mimeValues{}
	err := params.Add("animation", animationURL.String())
	if err != nil {
		return fmt.Errorf("Failed to add parameter: %w", err)
	}
	err = params.Add("caption", caption)
	if err != nil {
		return fmt.Errorf("Failed to add parameter: %w", err)
	}

	return b.sendInternal("sendAnimation", params, update)
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
	// trace("response from telegram for method %s: status %s, body %s", method, resp.Status, body)

	if resp.StatusCode != 200 {
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

func (m *mimeValues) AddFile(key string, value []byte, filename string) error {
	if m.bb == nil {
		m.bb = &bytes.Buffer{}
	}
	if m.writer == nil {
		m.writer = multipart.NewWriter(m.bb)
	}
	writer, err := m.writer.CreateFormFile(key, filename)
	if err != nil {
		return err
	}
	_, err = io.Copy(writer, bytes.NewReader(value))
	if err != nil {
		return err
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
