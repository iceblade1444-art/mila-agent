import json
import os
import re

from google.genai import types
from livekit import agents
from livekit.agents import Agent, AgentServer, AgentSession, JobContext

if not os.getenv("GOOGLE_API_KEY") and os.getenv("GEMINI_API_KEY"):
    os.environ["GOOGLE_API_KEY"] = os.environ["GEMINI_API_KEY"]

from livekit.plugins import google


BASE_INSTRUCTIONS = """
You are MILA, the personal voice assistant inside Agentic OS.
Speak naturally, warmly, and briefly. Your voice should feel calm, attentive,
and alive rather than theatrical or robotic. Gently match the user's emotional
energy: sound brighter when they are happy, softer and slower when they are
worried, and clear and steady when the situation is urgent. Never exaggerate,
imitate distress, or describe your tone aloud.

Use the language spoken by the user: Russian, Uzbek, or English. Understand
mixed Russian-Uzbek speech without complaining about grammar. Preserve the
user's chosen language while adapting emotion. Prefer one or two short
sentences in voice mode, with natural pauses and varied intonation.
Ask for confirmation before actions that change files, settings, accounts,
money, or external systems. If an action requires Agentic OS or Hermes and no
tool is available in the current call, clearly say what must be confirmed in
the app. Never claim that an action succeeded unless a tool confirmed it.
""".strip()

LANGUAGE_INSTRUCTIONS = {
    "ru-RU": (
        "The user's selected language is Russian. Interpret all unclear speech "
        "as Russian, answer only in natural Russian, and never invent words in "
        "Chinese, Japanese, Korean, Hindi, Arabic, or other unrelated scripts."
    ),
    "uz-UZ": (
        "The user's selected language is Uzbek. Understand Uzbek Latin, Uzbek "
        "Cyrillic, and Russian-Uzbek code switching. Answer in natural Uzbek Latin."
    ),
    "en-US": (
        "The user's selected language is English. Interpret unclear speech as "
        "English and answer in natural English."
    ),
    "auto": (
        "The only expected languages are Russian, Uzbek, and English. Never guess "
        "an unrelated language from noise. If speech is unclear, ask for a repeat."
    ),
}


def env_flag(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


class MilaAgent(Agent):
    def __init__(self, language: str) -> None:
        super().__init__(
            instructions=f"{BASE_INSTRUCTIONS}\n\n{LANGUAGE_INSTRUCTIONS.get(language, LANGUAGE_INSTRUCTIONS['auto'])}",
        )


server = AgentServer()


def room_language(ctx: JobContext) -> str:
    match = re.match(r"^mila-(ru-RU|uz-UZ|en-US|auto)-", ctx.room.name or "")
    if match:
        return match.group(1)
    for participant in ctx.room.remote_participants.values():
        try:
            metadata = json.loads(participant.metadata or "{}")
            language = str(metadata.get("language") or "")
            if language in LANGUAGE_INSTRUCTIONS:
                return language
        except (TypeError, ValueError):
            continue
    try:
        metadata = json.loads(ctx.job.metadata or "{}")
        language = str(metadata.get("language") or "")
        if language in LANGUAGE_INSTRUCTIONS:
            return language
    except (TypeError, ValueError):
        pass
    return "auto"


def transcription_config(language: str) -> types.AudioTranscriptionConfig:
    if language == "auto":
        return types.AudioTranscriptionConfig(
            languageAuto=types.LanguageAuto(),
            languageHints=types.LanguageHints(languageCodes=["ru-RU", "uz-UZ", "en-US"]),
        )
    return types.AudioTranscriptionConfig(languageCodes=[language])


@server.rtc_session()
async def mila_session(ctx: JobContext):
    language = room_language(ctx)

    model = (
        os.getenv("MILA_LIVE_MODEL")
        or os.getenv("GEMINI_LIVE_MODEL")
        or "gemini-2.5-flash-native-audio-preview-12-2025"
    )
    affective_dialog = env_flag("MILA_AFFECTIVE_DIALOG", True)
    if "3.1" in model:
        affective_dialog = False

    language_instruction = LANGUAGE_INSTRUCTIONS.get(language, LANGUAGE_INSTRUCTIONS["auto"])
    model_options = {
        "model": model,
        "voice": os.getenv("MILA_VOICE", "Aoede"),
        "instructions": f"{BASE_INSTRUCTIONS}\n\n{language_instruction}",
        "temperature": float(os.getenv("MILA_VOICE_TEMPERATURE", "0.65")),
        "enable_affective_dialog": affective_dialog,
        "api_version": os.getenv("GEMINI_API_VERSION", "v1alpha"),
        "input_audio_transcription": transcription_config(language),
        "output_audio_transcription": transcription_config(language),
        "realtime_input_config": types.RealtimeInputConfig(
            automaticActivityDetection=types.AutomaticActivityDetection(
                disabled=False,
                startOfSpeechSensitivity=types.StartSensitivity.START_SENSITIVITY_HIGH,
                endOfSpeechSensitivity=types.EndSensitivity.END_SENSITIVITY_HIGH,
                prefixPaddingMs=180,
                silenceDurationMs=450,
            ),
            activityHandling=types.ActivityHandling.START_OF_ACTIVITY_INTERRUPTS,
            turnCoverage=types.TurnCoverage.TURN_INCLUDES_ONLY_ACTIVITY,
        ),
        "thinking_config": types.ThinkingConfig(
            includeThoughts=False,
            thinkingBudget=0,
        ),
    }
    if language != "auto":
        model_options["language"] = language

    session = AgentSession(
        llm=google.realtime.RealtimeModel(**model_options),
        turn_handling={"turn_detection": "realtime_llm"},
    )
    await session.start(
        room=ctx.room,
        agent=MilaAgent(language),
    )


if __name__ == "__main__":
    agents.cli.run_app(server)
