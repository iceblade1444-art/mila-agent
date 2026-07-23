import json
import os

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


def env_flag(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


class MilaAgent(Agent):
    def __init__(self, language: str) -> None:
        language_hint = {
            "ru-RU": "The user's preferred language is Russian.",
            "uz-UZ": "The user's preferred language is Uzbek.",
            "en-US": "The user's preferred language is English.",
        }.get(language, "Automatically follow the user's language.")
        super().__init__(
            instructions=f"{BASE_INSTRUCTIONS}\n\n{language_hint}",
        )


server = AgentServer()


@server.rtc_session()
async def mila_session(ctx: JobContext):
    language = "auto"
    try:
        metadata = json.loads(ctx.job.metadata or "{}")
        language = str(metadata.get("language") or "auto")
    except (TypeError, ValueError):
        pass

    model = (
        os.getenv("MILA_LIVE_MODEL")
        or os.getenv("GEMINI_LIVE_MODEL")
        or "gemini-2.5-flash-native-audio-preview-12-2025"
    )
    affective_dialog = env_flag("MILA_AFFECTIVE_DIALOG", True)
    if "3.1" in model:
        affective_dialog = False

    session = AgentSession(
        llm=google.realtime.RealtimeModel(
            model=model,
            voice=os.getenv("MILA_VOICE", "Aoede"),
            instructions=BASE_INSTRUCTIONS,
            temperature=float(os.getenv("MILA_VOICE_TEMPERATURE", "0.8")),
            enable_affective_dialog=affective_dialog,
            api_version=os.getenv("GEMINI_API_VERSION", "v1alpha"),
        ),
    )
    await session.start(
        room=ctx.room,
        agent=MilaAgent(language),
    )


if __name__ == "__main__":
    agents.cli.run_app(server)
