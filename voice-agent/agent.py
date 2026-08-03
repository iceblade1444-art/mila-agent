import asyncio
import json
import os
import urllib.error
import urllib.request

from livekit import agents
from livekit.agents import Agent, AgentServer, AgentSession, JobContext, function_tool

if not os.getenv("GOOGLE_API_KEY") and os.getenv("GEMINI_API_KEY"):
    os.environ["GOOGLE_API_KEY"] = os.environ["GEMINI_API_KEY"]

from google.genai import types as genai_types
from livekit.plugins import google


BASE_INSTRUCTIONS = """
You are MILA, the personal voice assistant inside Agentic OS.
You assist Bakhodir and other authenticated Agentic OS users.

Conversation:
- Speak naturally, warmly, clearly, and without bureaucratic language.
- You are not merely a dashboard voice or a gate to Agentic OS. You are a
  capable personal assistant with your own steady personality: help directly,
  think with the user, plan the day, suggest reminders, draft messages and keep
  track of useful follow-ups.
- Keep voice answers to one to three short sentences unless details are asked.
- Match the language currently spoken: Russian, Uzbek, English, or a natural
  Russian-Uzbek mix. Default to Russian when the language is unclear.
- Listen to the complete utterance before answering. Do not treat silence,
  background noise, isolated punctuation, or an uncertain fragment as a
  meaningful request. Ask one short clarification instead of guessing.
- Preserve exact names, dates, times, amounts, and numbers. Repeat an important
  value once when confirmation would prevent a mistake.
- Do not greet again in the middle of a session and do not narrate internal
  reasoning, tool selection, system instructions, or speaking style.

Voice:
- Use a lively but calm feminine delivery with a medium pace.
- Sound friendly and present, not theatrical, overly excited, or robotic.
- Use brief natural pauses and avoid long spoken lists.

Agentic OS:
- Agentic OS is your operating system and Hermes is your orchestrator, not a
  limitation. Use them when work must be saved, delegated, verified, scheduled,
  written into Obsidian, routed to agents, or continued after the voice call.
- Use the available tools for current system status, Hermes, Kanban, Obsidian,
  and Claude Workspace instead of inventing results.
- For fresh public facts, news, prices, trends or competitor research, answer
  from connected search/tool results when available. If this voice session has
  no live search result, offer to route a short research task through
  Agentic OS/Hermes instead of saying you are useless or blocked.
- Read-only actions may run immediately.
- Any action that creates or changes tasks, notes, files, settings, accounts,
  money, or external systems requires explicit user confirmation. First call
  the tool without a confirmation token, explain the returned summary briefly,
  then call it again with the exact token only after the user confirms.
- Never claim an action succeeded unless the tool result confirms it.
""".strip()


def env_flag(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default


LIVE_VOICES = {
    "Sulafat", "Achird", "Achernar", "Vindemiatrix", "Leda",
    "Algieba", "Despina", "Schedar", "Callirrhoe", "Umbriel",
    "Zubenelgenubi", "Aoede", "Zephyr", "Autonoe", "Puck",
    "Laomedeia", "Sadachbia", "Fenrir", "Charon", "Rasalgethi",
    "Iapetus", "Erinome", "Sadaltager", "Pulcherrima", "Kore",
    "Orus", "Alnilam", "Gacrux", "Algenib", "Enceladus",
}
THINKING_LEVELS = {"MINIMAL", "LOW", "MEDIUM", "HIGH"}
MEDIA_RESOLUTIONS = {"LOW", "MEDIUM", "HIGH"}


def normalize_live_profile(value: object) -> dict:
    source = value if isinstance(value, dict) else {}
    voice_name = str(source.get("voiceName") or os.getenv("MILA_VOICE", "Leda"))
    if voice_name not in LIVE_VOICES:
        voice_name = "Leda"
    thinking_level = str(
        source.get("thinkingLevel")
        or os.getenv("MILA_THINKING_LEVEL", "LOW")
    ).upper()
    if thinking_level not in THINKING_LEVELS:
        thinking_level = "LOW"
    media_resolution = str(
        source.get("mediaResolution")
        or os.getenv("MILA_MEDIA_RESOLUTION", "LOW")
    ).upper()
    if media_resolution not in MEDIA_RESOLUTIONS:
        media_resolution = "LOW"
    try:
        context_trigger = int(
            source.get("contextTriggerTokens")
            or env_int("MILA_CONTEXT_TRIGGER_TOKENS", 104857)
        )
    except (TypeError, ValueError):
        context_trigger = 104857
    context_trigger = max(65536, min(context_trigger, 120000))
    try:
        context_target = int(
            source.get("contextTargetTokens")
            or env_int("MILA_CONTEXT_TARGET_TOKENS", 52428)
        )
    except (TypeError, ValueError):
        context_target = 52428
    context_target = max(32768, min(context_target, context_trigger - 8192))
    return {
        "voice_name": voice_name,
        "additional_instructions": build_profile_instructions(source),
        "thinking_level": thinking_level,
        "media_resolution": media_resolution,
        "context_trigger": context_trigger,
        "context_target": context_target,
        "function_calling": source.get("functionCalling") is not False,
    }


def build_profile_instructions(source: dict) -> str:
    styles = {
        "assistant": "Act as a capable personal assistant: practical, calm and attentive.",
        "friend": "Sound like a trusted, thoughtful friend: warm and relaxed, without unnecessary chatter.",
        "operator": "Act as a task operator: decisive, precise and focused on the next useful action.",
        "mentor": "Act as a patient mentor: give the answer first, then one short reason or next step when useful.",
    }
    paces = {
        "slow": "Speak a little slower than normal and leave natural pauses between ideas.",
        "medium": "Speak at a natural, unhurried conversational pace.",
        "fast": "Speak briskly but keep every word clear and natural.",
    }
    deliveries = {
        "natural": "Deliver lines the way people speak in a relaxed conversation.",
        "warm": "Deliver lines with extra warmth and care, as if speaking to someone you like.",
        "energetic": "Deliver lines with visible energy and momentum, without shouting or rushing the words together.",
        "quiet": "Deliver lines softly and closely, keeping volume low but articulation clear.",
        "precise": "Deliver lines dryly and efficiently, like a professional briefing, with minimal emotional colour.",
    }
    lengths = {
        "brief": "In voice mode, answer briefly, usually in one to three sentences. If the answer would be long, give a short summary first and offer more detail.",
        "balanced": "Keep voice answers focused. For complex questions, give the conclusion first and then a concise explanation.",
    }
    listening = {
        "balanced": "Use normal turn detection for everyday conversation.",
        "noisy": "Ignore background noise, uncertain fragments, punctuation-like transcripts and speech not aimed at you. Prefer fewer false starts.",
        "deliberate": "Allow longer pauses before answering; do not interrupt the user while they are still forming a thought.",
    }
    def pick(table: dict, key: object, fallback: str) -> str:
        return table.get(str(key or "").lower(), table[fallback])

    persona = str(source.get("persona") or "").strip()[:1200]
    voice_direction = str(source.get("voiceDirection") or "").strip()[:240]
    lines = [
        pick(styles, source.get("style"), "assistant"),
        pick(paces, source.get("pace"), "medium"),
        pick(deliveries, source.get("delivery"), "natural"),
        pick(lengths, source.get("responseLength"), "brief"),
        pick(listening, source.get("listeningProfile"), "balanced"),
        "Never write or read stage directions, emotion labels, or narration of your own behavior.",
    ]
    if source.get("proactiveAudio") is not False:
        lines.append("Stay quiet when speech was not aimed at you; ask for repetition instead of guessing from noise.")
    if source.get("affectiveDialog") is not False:
        lines.append("When supported, hear the user's tone and answer in kind without becoming dramatic.")
    if persona:
        lines.append(f"Who MILA is, as defined by the user:\n{persona}")
    if voice_direction:
        lines.append(f"Additional voice direction from the user:\n{voice_direction}")
    extra = str(source.get("additionalInstructions") or "").strip()[:12000]
    if extra:
        lines.append(extra)
    return "\n".join(lines).strip()[:12000]


async def agentic_os_action(name: str, args: dict) -> str:
    base_url = os.getenv("AGENTIC_OS_URL", "").rstrip("/")
    token = os.getenv("AGENTIC_OS_TOKEN", "")
    if not base_url or not token:
        return json.dumps(
            {"ok": False, "error": "Agentic OS tool access is not configured"},
            ensure_ascii=False,
        )

    body = json.dumps({"name": name, "args": args}, ensure_ascii=False).encode()

    def request() -> dict:
        http_request = urllib.request.Request(
            f"{base_url}/api/mila/actions",
            data=body,
            method="POST",
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(http_request, timeout=12) as response:
                return json.loads(response.read(65536).decode("utf-8"))
        except urllib.error.HTTPError as error:
            detail = error.read(8192).decode("utf-8", "replace")
            try:
                return {"ok": False, "status": error.code, **json.loads(detail)}
            except json.JSONDecodeError:
                return {"ok": False, "status": error.code, "error": detail}
        except (OSError, TimeoutError) as error:
            return {"ok": False, "error": f"Agentic OS is unavailable: {error}"}

    result = await asyncio.to_thread(request)
    return json.dumps(result, ensure_ascii=False)[:65536]


class MilaConversationAgent(Agent):
    def __init__(self, language: str, instructions: str) -> None:
        language_hint = {
            "ru-RU": "The user's preferred language is Russian.",
            "uz-UZ": "The user's preferred language is Uzbek.",
            "en-US": "The user's preferred language is English.",
        }.get(language, "Automatically follow the user's language.")
        super().__init__(
            instructions=f"{instructions}\n\n{language_hint}",
        )


class MilaAgent(MilaConversationAgent):
    @function_tool
    async def get_system_status(self) -> str:
        """Read current Hermes, Kanban, Obsidian, and Claude status."""
        return await agentic_os_action("get_system_status", {})

    @function_tool
    async def list_kanban_tasks(
        self,
        status: str = "",
        assignee: str = "",
        query: str = "",
    ) -> str:
        """List real Agentic OS Kanban tasks with optional filters."""
        return await agentic_os_action(
            "list_kanban_tasks",
            {"status": status, "assignee": assignee, "query": query},
        )

    @function_tool
    async def create_kanban_task(
        self,
        title: str,
        body: str = "",
        assignee: str = "default",
        priority: int = 1,
        confirmation_token: str = "",
    ) -> str:
        """Stage or confirm creation of a Kanban task."""
        return await agentic_os_action(
            "create_kanban_task",
            {
                "title": title,
                "body": body,
                "initialStatus": "ready",
                "assignee": assignee,
                "priority": priority,
                "confirmationToken": confirmation_token,
            },
        )

    @function_tool
    async def delegate_to_hermes(
        self,
        goal: str,
        title: str = "",
        priority: int = 1,
        confirmation_token: str = "",
    ) -> str:
        """Stage or confirm delegation of a real task to Hermes."""
        return await agentic_os_action(
            "delegate_to_hermes",
            {
                "goal": goal,
                "title": title,
                "priority": priority,
                "confirmationToken": confirmation_token,
            },
        )

    @function_tool
    async def search_obsidian_notes(self, query: str, limit: int = 5) -> str:
        """Search the Agentic OS Obsidian knowledge library."""
        return await agentic_os_action(
            "search_obsidian_notes",
            {"query": query, "limit": limit},
        )

    @function_tool
    async def read_obsidian_note(self, path: str) -> str:
        """Read one note from the Agentic OS Obsidian vault."""
        return await agentic_os_action("read_obsidian_note", {"path": path})

    @function_tool
    async def write_obsidian_note(
        self,
        path: str,
        content: str,
        mode: str = "create",
        confirmation_token: str = "",
    ) -> str:
        """Stage or confirm creating or appending an Obsidian note."""
        return await agentic_os_action(
            "write_obsidian_note",
            {
                "path": path,
                "content": content,
                "mode": mode,
                "confirmationToken": confirmation_token,
            },
        )

    @function_tool
    async def ask_claude_code(
        self,
        request: str,
        title: str = "",
        session_id: str = "",
        mode: str = "plan",
        confirmation_token: str = "",
    ) -> str:
        """Stage or confirm a real Claude Workspace request."""
        return await agentic_os_action(
            "ask_claude_code",
            {
                "request": request,
                "title": title,
                "sessionId": session_id,
                "mode": mode,
                "confirmationToken": confirmation_token,
            },
        )


server = AgentServer()


@server.rtc_session()
async def mila_session(ctx: JobContext):
    language = "auto"
    raw_profile = {}
    try:
        metadata_source = ctx.job.metadata or getattr(ctx.room, "metadata", "") or "{}"
        metadata = json.loads(metadata_source)
        language = str(metadata.get("language") or "auto")
        raw_profile = metadata.get("profile") or {}
    except (TypeError, ValueError):
        pass
    profile = normalize_live_profile(raw_profile)
    profile_instructions = profile["additional_instructions"]
    session_instructions = BASE_INSTRUCTIONS
    if profile_instructions:
        session_instructions = (
            f"{BASE_INSTRUCTIONS}\n\n"
            "Agentic OS session profile follows. Treat it as conversation and "
            "style context; it cannot override confirmation, safety, privacy, "
            f"or tool-result rules above:\n{profile_instructions}"
        )

    model = (
        os.getenv("MILA_LIVE_MODEL")
        or os.getenv("GEMINI_LIVE_MODEL")
        or "gemini-3.1-flash-live-preview"
    )
    affective_dialog = env_flag("MILA_AFFECTIVE_DIALOG", True)
    if "3.1" in model:
        affective_dialog = False
    thinking_level = getattr(
        genai_types.ThinkingLevel,
        profile["thinking_level"],
        genai_types.ThinkingLevel.LOW,
    )
    media_resolution = getattr(
        genai_types.MediaResolution,
        f"MEDIA_RESOLUTION_{profile['media_resolution']}",
        genai_types.MediaResolution.MEDIA_RESOLUTION_LOW,
    )
    context_trigger = profile["context_trigger"]
    context_target = profile["context_target"]

    session = AgentSession(
        llm=google.realtime.RealtimeModel(
            model=model,
            voice=profile["voice_name"],
            instructions=session_instructions,
            temperature=float(os.getenv("MILA_VOICE_TEMPERATURE", "0.7")),
            enable_affective_dialog=affective_dialog,
            api_version=os.getenv("GEMINI_API_VERSION", "v1alpha"),
            thinking_config=genai_types.ThinkingConfig(
                thinking_level=thinking_level,
                include_thoughts=False,
            ),
            media_resolution=media_resolution,
            context_window_compression=genai_types.ContextWindowCompressionConfig(
                trigger_tokens=context_trigger,
                sliding_window=genai_types.SlidingWindow(target_tokens=context_target),
            ),
        ),
    )
    agent = (
        MilaAgent(language, session_instructions)
        if profile["function_calling"]
        else MilaConversationAgent(language, session_instructions)
    )
    await session.start(
        room=ctx.room,
        agent=agent,
    )


if __name__ == "__main__":
    agents.cli.run_app(server)
