package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"mime/multipart"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/davecgh/go-spew/spew"
)

// ------------
// Telegram API
// ------------
type telegramBot struct {
	Token             string
	lastKnownUpdateID int
}

type telegramResponse struct {
	OK          bool                        `json:"ok"`
	Result      json.RawMessage             `json:"result"`
	ErrorCode   int                         `json:"error_code"`
	Description string                      `json:"description"`
	Parameters  *telegramResponseParameters `json:"parameters"`
}

type telegramResponseParameters struct {
	MigrateToChatID int64 `json:"migrate_to_chat_id"` // optional
	RetryAfter      int   `json:"retry_after"`        // optional
}

type telegramUpdate struct {
	// fields we're not interested in are not here
	ID      int              `json:"update_id"`
	Message *telegramMessage `json:"message"`

	// // inline
	// InlineQuery        *telegramInlineQuery        `json:"inline_query"`
	// ChosenInlineResult *telegramChosenInlineResult `json:"chosen_inline_result"`
}

type telegramMessage struct {
	ID   int           `json:"message_id"`
	From *telegramUser `json:"from"`
	Date telegramDate  `json:"date"`
	Chat telegramChat  `json:"chat"`
	Text string        `json:"text"`
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
	return command[1:] // remove slash in the beginning
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

type telegramUser struct {
	ID           int    `json:"id"`
	Bot          bool   `json:"is_bot"`
	FirstName    string `json:"first_name"`
	LastName     string `json:"last_name"`
	Username     string `json:"username"`
	LanguageCode string `json:"language_code"`
}

type telegramChat struct {
	ID int64 `json:"id"`
}

type telegramDate time.Time

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

func (b *telegramBot) getUpdates() ([]telegramUpdate, error) {
	params := url.Values{}
	if b.lastKnownUpdateID != 0 {
		params.Add("offset", strconv.Itoa(b.lastKnownUpdateID+1))
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
		spew.Dump(response)
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
	largestID := 0
	for _, update := range updates {
		if update.ID > largestID {
			largestID = update.ID
		}
	}

	b.lastKnownUpdateID = largestID

	return updates, nil
}

func (b *telegramBot) sendMessage(chatID int64, message string) error {
	params := mimeValues{}
	params.Add("chat_id", chatID)
	params.Add("text", message)

	return b.sendInternal("sendMessage", params)
}

func (b *telegramBot) sendChatAction(chatID int64, action string) error {
	params := mimeValues{}
	params.Add("chat_id", chatID)
	params.Add("action", action)

	return b.sendInternal("sendChatAction", params)
}

func (b *telegramBot) sendPhoto(chatID int64, photo []byte, filename string, caption string) error {
	params := mimeValues{}
	params.Add("chat_id", chatID)
	params.AddFile("photo", photo, filename)
	params.Add("caption", caption)

	return b.sendInternal("sendPhoto", params)
}

func (b *telegramBot) sendDocument(chatID int64, document []byte, filename string, caption string) error {
	params := mimeValues{}
	params.Add("chat_id", chatID)
	params.AddFile("document", document, filename)
	params.Add("caption", caption)

	return b.sendInternal("sendDocument", params)
}

// empty struct is ready to use
type mimeValues struct {
	writer *multipart.Writer
	bb     *bytes.Buffer
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

func (b *telegramBot) sendInternal(method string, params mimeValues) error {
	if params.writer == nil {
		return fmt.Errorf("sendInternal() was called with nil mime params writer")
	}
	if params.bb == nil {
		return fmt.Errorf("sendInternal() was called with nil mime params bytes buffer")
	}

	err := params.writer.Close()
	if err != nil {
		return err
	}

	url := fmt.Sprintf("https://api.telegram.org/bot%s/%s", b.Token, method)
	req, err := http.NewRequest("POST", url, params.bb)
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", params.writer.FormDataContentType())

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
	trace("response from telegram %s: status %s, body %s", method, resp.Status, body)

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
