# frozen_string_literal: true

# app.rb (микросервис API)
require 'sinatra'
require 'json'
require 'telegram/bot'
require 'byebug'
require 'jwt'
require 'openssl'
require 'dotenv'

Dotenv.load

BOT_TOKEN = ENV['BOT_TOKEN']
WEBHOOK_URL = "#{ENV['NGROK_ID']}.ngrok-free.app/webhook"
HOST_URL = "#{ENV['NGROK_ID']}.ngrok-free.app"
WEB_APP_URL = ENV['WEB_APP_URL']
JWT_SECRET = "test_secret_key"

configure do
  # Configure permitted hosts for all environments
  set :host_authorization, { permitted_hosts: [HOST_URL, "127.0.0.1", "::1", "localhost"] }
end

before do
  # Разрешаем CORS (важно для WebApp!)
  headers 'Access-Control-Allow-Origin' => '*',
          'Access-Control-Allow-Methods' => ['OPTIONS', 'GET', 'POST', 'PUT', 'DELETE'],
          'Access-Control-Allow-Headers' => 'Content-Type'

  request.body.rewind
  @data = JSON.parse(request.body.read) rescue {}
end

get '/' do
  'Hello, World!'
end

# Установка вебхука
Telegram::Bot::Client.run(BOT_TOKEN) do |bot|
  bot.api.set_webhook(url: WEBHOOK_URL)
  puts "Вебхук установлен: #{WEBHOOK_URL}"
end

# Обработчик вебхука
post '/webhook' do
  bot = Telegram::Bot::Client.new(BOT_TOKEN)
  message = @data['message']
  web_app_data = @data['web_app_data']

  puts "Получены данные: #{JSON.pretty_generate(@data)}"

  # Обработка обычных сообщений
  if message
    chat_id = message['chat']['id']
    text = message['text']

    case text
    when '/start'
      markup = Telegram::Bot::Types::ReplyKeyboardMarkup.new(
        keyboard: [
          [{ text: 'QR' }, { text: 'Сделать заказ' }],
          [{ text: 'Акции' }, { text: 'Заказы' }]
        ],
        resize_keyboard: true # Опционально: подгоняет размер клавиатуры
      )

      bot.api.send_message(chat_id: chat_id, text: 'Выберите действие:', reply_markup: markup)
    when 'QR'
      bot.api.send_message(chat_id: chat_id, text: 'Здесь будет QR-код')
    when 'Сделать заказ'
      inline_markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(
        inline_keyboard: [
          [{
            text: '🍕 Заказать',
            web_app: { url: "#{WEB_APP_URL}?screen=menu&another_param=another_value1" }
          }]
        ]
      )

      bot.api.send_message(chat_id: chat_id, text: 'Переходи по ссылке и делай самый вкусный заказ', reply_markup: inline_markup)
    when 'Акции'
      inline_markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(
        inline_keyboard: [
          [{
            text: '🍕 Акции',
            web_app:  { url: "#{WEB_APP_URL}?screen=promotions&another_param=another_value2" }
          }]
        ]
      )

      bot.api.send_message(chat_id: chat_id, text: 'Список доступных акций', reply_markup: inline_markup)
    when 'Заказы'
      inline_markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(
        inline_keyboard: [
          [{
            text: '🍕 Заказы',
            web_app:  { url: "#{WEB_APP_URL}?screen=orders&another_param=another_value3" }
          }]
        ]
      )

      bot.api.send_message(chat_id: chat_id, text: 'По этой ссылке пойдешь - историю заказов найдешь', reply_markup: inline_markup)
    end

  # Обработка данных из мини-приложения (WebApp)
  elsif web_app_data
    user_id = @data['from']['id']
    data = JSON.parse(web_app_data['data'])

    bot.api.send_message(chat_id: user_id, text: "Спасибо за заказ! Вы выбрали: #{data['pizza']} за #{data['price']} ₽.")
  end

  status 200
end

# Обработка OPTIONS-запроса для /auth
options '/auth' do
  status 200
end

# Маршрут для аутентификации
post '/auth' do
  unless @data['initData'] && valid_init_data?(@data['initData'], BOT_TOKEN)
    return { error: 'Invalid initData' }.to_json
  end

  # Извлекаем user_id из initData
  init_data = URI.decode_www_form(@data['initData']).to_h
  user_id = JSON.parse(init_data['user'])['id'] rescue nil

  unless user_id
    return { error: 'User ID not found' }.to_json
  end

  # Генерируем токены
  tokens = generate_tokens(user_id)

  # Возвращаем токены
  {
    status: 'success',
    tokens: tokens,
    user_id: user_id
  }.to_json
end

# Валидация initData из Telegram
def valid_init_data?(init_data_str, bot_token)
  init_data = URI.decode_www_form(init_data_str).to_h
  secret_key = OpenSSL::HMAC.digest('sha256', 'WebAppData', bot_token)
  data_check = init_data.except('hash').sort.map { |k, v| "#{k}=#{v}" }.join("\n")
  computed_hash = OpenSSL::HMAC.hexdigest('sha256', secret_key, data_check)
  computed_hash == init_data['hash']
end

# Генерация JWT-токенов
def generate_tokens(user_id)
  access_token = JWT.encode(
    { user_id: user_id, exp: Time.now.to_i + 3600 }, # 1 час
    JWT_SECRET,
    'HS256'
  )

  refresh_token = JWT.encode(
    { user_id: user_id, exp: Time.now.to_i + 86400 * 7 }, # 7 дней
    JWT_SECRET,
    'HS256'
  )

  { access_token: access_token, refresh_token: refresh_token }
end

# Запуск сервера
puts "Сервер запущен на порту #{settings.port}"