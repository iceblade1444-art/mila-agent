import asyncio
import os

import requests
from livekit import rtc


BACKEND_URL = os.getenv("MILA_INTERNAL_URL", "http://mila-backend:8787")
LIVEKIT_URL = os.getenv("LIVEKIT_INTERNAL_URL", "ws://livekit:7880")


def issue_credentials() -> dict:
    admin_token = os.environ["ADMIN_TOKEN"]
    issued = requests.post(
        f"{BACKEND_URL}/admin/connection-code",
        headers={"X-Admin-Token": admin_token},
        json={
            "label": "LiveKit smoke test",
            "owner": {
                "id": "livekit-smoke-test",
                "name": "MILA verifier",
                "role": "System",
            },
        },
        timeout=10,
    )
    issued.raise_for_status()
    connected = requests.post(
        f"{BACKEND_URL}/v1/auth/device",
        json={"code": issued.json()["code"]},
        timeout=10,
    )
    connected.raise_for_status()
    room = requests.post(
        f"{BACKEND_URL}/v1/voice/livekit-token",
        headers={"Authorization": f"Bearer {connected.json()['token']}"},
        json={"language": "ru-RU"},
        timeout=10,
    )
    room.raise_for_status()
    return room.json()


async def main() -> None:
    credentials = issue_credentials()
    room = rtc.Room()
    audio_received = asyncio.Event()
    transcript_received = asyncio.Event()
    audio_frames = 0
    transcripts: list[str] = []

    async def consume_audio(track: rtc.AudioTrack) -> None:
        nonlocal audio_frames
        async for _event in rtc.AudioStream(track):
            audio_frames += 1
            audio_received.set()
            if audio_frames >= 3:
                break

    @room.on("track_subscribed")
    def on_track_subscribed(track, _publication, _participant) -> None:
        if track.kind == rtc.TrackKind.KIND_AUDIO:
            asyncio.create_task(consume_audio(track))

    async def on_transcription(reader, _participant_identity: str) -> None:
        chunks: list[str] = []
        async for chunk in reader:
            content = chunk.content
            chunks.append(
                content.decode("utf-8") if isinstance(content, bytes) else str(content),
            )
        text = "".join(chunks).strip()
        if text:
            transcripts.append(text)
            transcript_received.set()

    room.register_text_stream_handler("lk.transcription", on_transcription)
    await room.connect(LIVEKIT_URL, credentials["participant_token"])
    await room.local_participant.send_text(
        "Ответь по-русски одной фразой: Привет, я слышу тебя.",
        topic="lk.chat",
    )

    await asyncio.wait_for(audio_received.wait(), timeout=30)
    try:
        await asyncio.wait_for(transcript_received.wait(), timeout=5)
    except TimeoutError:
        pass
    await room.disconnect()
    print(
        {
            "connected": True,
            "audio_frames": audio_frames,
            "transcript": transcripts[-1] if transcripts else "",
        },
    )


if __name__ == "__main__":
    asyncio.run(main())
