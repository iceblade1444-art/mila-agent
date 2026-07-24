import json
import os

from google.genai import types
from livekit import agents
from livekit.agents import Agent, AgentServer, AgentSession, JobContext, RoomInputOptions

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

React only to clear human speech. Ignore silence, breathing, keyboard sounds,
speaker echo, background audio, isolated punctuation, and transcripts such as
"<noise>". Never guess a sentence from an unclear sound. If a phrase is too
unclear to understand, wait quietly for the user to speak again.
""".strip()

LANGUAGE_HINTS = {
    "ru-RU": "The user's preferred spoken language is Russian. Listen for Russian first and answer in Russian unless the user clearly switches language.",
    "uz-UZ": "The user's preferred spoken language is Uzbek. Listen for Uzbek first and answer in Uzbek unless the user clearly switches language.",
    "en-US": "The user's preferred spoken language is English. Listen for English first and answer in English unless the user clearly switches language.",
}


def normalize_language(value: str | None) -> str:
    raw = str(value or "auto").strip()
    if raw in {"ru-RU", "uz-UZ", "en-US", "auto"}:
        return raw
    if raw.startswith("ru"):
        return "ru-RU"
    if raw.startswith("uz"):
        return "uz-UZ"
    if raw.startswith("en"):
        return "en-US"
    return "auto"


def language_from_metadata(value: str | None) -> str:
    try:
        metadata = json.loads(value or "{}")
    except (TypeError, ValueError):
        return "auto"
    return normalize_language(metadata.get("language"))


def env_flag(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


class MilaAgent(Agent):
    def __init__(self, language: str) -> None:
        language_hint = LANGUAGE_HINTS.get(language, "Automatically follow the user's language.")
        super().__init__(
            instructions=f"{BASE_INSTRUCTIONS}\n\n{language_hint}",
        )


server = AgentServer()


@server.rtc_session()
async def mila_session(ctx: JobContext):
    participant = await ctx.wait_for_participant()
    language = language_from_metadata(participant.metadata)
    if language == "auto":
        language = language_from_metadata(ctx.job.metadata)

    model = (
        os.getenv("MILA_LIVE_MODEL")
        or os.getenv("GEMINI_LIVE_MODEL")
        or "gemini-2.5-flash-native-audio-preview-12-2025"
    )
    affective_dialog = env_flag("MILA_AFFECTIVE_DIALOG", True)
    if "3.1" in model:
        affective_dialog = False

    instructions = f"{BASE_INSTRUCTIONS}\n\n{LANGUAGE_HINTS.get(language, 'Automatically follow the user language.')}"
    model_kwargs = {
        "model": model,
        "voice": os.getenv("MILA_VOICE", "Aoede"),
        "instructions": instructions,
        "temperature": float(os.getenv("MILA_VOICE_TEMPERATURE", "0.8")),
        "enable_affective_dialog": affective_dialog,
        "proactivity": False,
        "realtime_input_config": types.RealtimeInputConfig(
            automatic_activity_detection=types.AutomaticActivityDetection(
                disabled=False,
                start_of_speech_sensitivity=types.StartSensitivity.START_SENSITIVITY_HIGH,
                end_of_speech_sensitivity=types.EndSensitivity.END_SENSITIVITY_HIGH,
                prefix_padding_ms=160,
                silence_duration_ms=750,
            ),
            activity_handling=types.ActivityHandling.START_OF_ACTIVITY_INTERRUPTS,
            turn_coverage=types.TurnCoverage.TURN_INCLUDES_ONLY_ACTIVITY,
        ),
        "api_version": os.getenv("GEMINI_API_VERSION", "v1alpha"),
    }
    if language != "auto":
        model_kwargs["language"] = language

    session = AgentSession(
        llm=google.realtime.RealtimeModel(
            **model_kwargs,
        ),
        min_interruption_duration=0.75,
        min_interruption_words=2,
        false_interruption_timeout=1.2,
    )
    await session.start(
        room=ctx.room,
        agent=MilaAgent(language),
        room_input_options=RoomInputOptions(
            audio_enabled=True,
            text_enabled=False,
            video_enabled=False,
            participant_identity=participant.identity,
            pre_connect_audio=False,
            close_on_disconnect=True,
        ),
    )


if __name__ == "__main__":
    agents.cli.run_app(server)
