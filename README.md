# Derpibooru Telegram Bot

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
First, make sure you have required gems installed:
```
bundle
```

Or you can install the gems manually:
```
gem install telegram-bot-ruby httparty memcached awesome_print net-http-persistent typhoeus
```

Then you can proceed with running it:
```
./derpibooru_bot.rb
```

It will show in console and log to `derpibooru_bot.log` file all interactions it has.
