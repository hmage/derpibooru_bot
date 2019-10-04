# [Derpibooru Telegram Bot](https://t.me/DerpibooruBot)

Hello! I'm a bot by @hmage that sends you images of ponies.

To get a random top scoring picture: /pony

To search for Celestia: /pony Celestia

You get the idea :)

## Setup and configuring

You will need to have `settings.yaml` file with keys for both Telegram Bot API and Derpibooru, like this:
```yaml
telegram_token: some_secret_telegram_token
derpibooru_key: some_secret_derpibooru_key
```

Replace them with your actual tokens.

## Running
First, build the bot:
```
go build
```

Then you can proceed with running it:
```
./derpibooru_bot
```
