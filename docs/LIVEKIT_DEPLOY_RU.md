# MILA Live через LiveKit

MILA использует LiveKit как устойчивый WebRTC-транспорт между мобильным
приложением и серверным Gemini Live агентом. Gemini API key, LiveKit secret и
доступ к Agentic OS остаются только на сервере.

## Сервисы

- `livekit` - сигнализация и WebRTC-медиа.
- `mila-voice-agent` - серверный Gemini 3.1 Flash Live агент.
- `mila-backend` - единая авторизация и выдача коротких комнатных JWT.

## Публичная сеть

В Nginx Proxy Manager у хоста `agent.milanapremium.uz` добавьте Custom Location:

- Location: `/rtc`
- Scheme: `http`
- Forward hostname/IP: `172.16.10.6`
- Forward port: `7880`
- Websockets Support: включено

На роутере или внешнем firewall направьте на `172.16.10.6`:

- `50000/UDP` - основной WebRTC media transport.
- `7881/TCP` - резервный ICE/TCP transport.

Из диапазона `50000-60000/UDP` используется единый UDP-mux порт `50000`.
Это сохраняет прямой низколатентный WebRTC transport без публикации всего
диапазона на Docker-хосте.

## Запуск

```bash
cd /opt/mila
bash scripts/configure-livekit-env.sh
docker compose up -d --build
docker compose ps
docker compose logs --tail 100 livekit mila-voice-agent mila-backend
```

Не размещайте содержимое `backend/.env` в GitHub и не отправляйте LiveKit API
secret в мобильное приложение.
