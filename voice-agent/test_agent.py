"""Pure-function tests for the voice agent's instruction building.

Run with: python -m unittest discover -s voice-agent -p "test_*.py"

Importing agent.py pulls in livekit and google plugins, which are heavy and not
installed on a plain CI runner, so the module under test is loaded from source
with those imports stubbed out.
"""
import json
import sys
import types
import unittest
import unittest.mock
from pathlib import Path


def _load_agent_module():
    """Import agent.py with its third-party dependencies stubbed."""
    stubs = {}

    livekit = types.ModuleType("livekit")
    agents = types.ModuleType("livekit.agents")

    class _Agent:
        def __init__(self, *args, **kwargs):
            self.kwargs = kwargs

    agents.Agent = _Agent
    agents.AgentServer = lambda *a, **k: types.SimpleNamespace(
        rtc_session=lambda *aa, **kk: (lambda fn: fn),
    )
    agents.AgentSession = object
    agents.JobContext = object
    agents.function_tool = lambda fn: fn
    agents.cli = types.SimpleNamespace(run_app=lambda *a, **k: None)
    livekit.agents = agents
    plugins = types.ModuleType("livekit.plugins")
    plugins.google = types.SimpleNamespace(realtime=types.SimpleNamespace(RealtimeModel=object))
    livekit.plugins = plugins

    genai = types.ModuleType("google.genai")
    genai.types = types.SimpleNamespace(
        ThinkingLevel=types.SimpleNamespace(LOW="LOW", HIGH="HIGH"),
        MediaResolution=types.SimpleNamespace(LOW="LOW", HIGH="HIGH"),
    )
    google_pkg = types.ModuleType("google")
    google_pkg.genai = genai

    stubs.update({
        "livekit": livekit,
        "livekit.agents": agents,
        "livekit.plugins": plugins,
        "google": google_pkg,
        "google.genai": genai,
    })
    for name, module in stubs.items():
        sys.modules.setdefault(name, module)

    source = (Path(__file__).parent / "agent.py").read_text(encoding="utf-8")
    module = types.ModuleType("agent_under_test")
    module.__file__ = str(Path(__file__).parent / "agent.py")
    exec(compile(source, module.__file__, "exec"), module.__dict__)  # noqa: S102
    return module


agent = _load_agent_module()


class ProfileInstructionsTest(unittest.TestCase):
    def test_speaking_rules_travel_to_every_call(self):
        """The phone path must carry the same rules the browser prompt has."""
        text = agent.build_profile_instructions({})
        # Stage directions were being spoken aloud; the ban states why.
        self.assertIn("Never write stage directions", text)
        self.assertIn("spoken aloud exactly as written", text)
        self.assertIn("[whispers]", text)
        # Hesitation makes speech human, but must not become a tic.
        self.assertIn("Хмм…", text)
        self.assertIn("Let me think…", text)
        self.assertIn("O'ylab ko'ray…", text)
        self.assertIn("one reply out of four", text)
        self.assertIn("Never hesitate before something you already know", text)
        # The recogniser must not be allowed to invent a fourth language.
        self.assertIn("Russian, Uzbek or English", text)
        self.assertIn("ask them to repeat", text)

    def test_persona_and_direction_are_bounded_and_kept(self):
        text = agent.build_profile_instructions({
            "persona": "Тебя зовут Мила. Ты спокойная и прямая.",
            "voiceDirection": "Speak like a calm night-radio host",
            "style": "friend",
            "delivery": "quiet",
        })
        self.assertIn("Тебя зовут Мила", text)
        self.assertIn("night-radio host", text)
        self.assertIn("trusted, thoughtful friend", text)
        self.assertIn("softly and closely", text)

    def test_unknown_choices_fall_back_instead_of_raising(self):
        text = agent.build_profile_instructions({"style": "pirate", "delivery": "opera", "pace": "warp"})
        self.assertIn("capable personal assistant", text)
        self.assertIn("relaxed conversation", text)
        self.assertLessEqual(len(text), 12000)

    def test_result_stays_within_the_profile_budget(self):
        text = agent.build_profile_instructions({"additionalInstructions": "x" * 20000})
        self.assertLessEqual(len(text), 12000)


class ServedInstructionTest(unittest.TestCase):
    """Agentic OS owns the prompt; this agent only asks for it."""

    def setUp(self):
        self.env = unittest.mock.patch.dict(
            "os.environ",
            {"AGENTIC_OS_URL": "http://agentic-os:8787", "AGENTIC_OS_TOKEN": "t0ken"},
        )
        self.env.start()
        self.addCleanup(self.env.stop)

    def _response(self, payload):
        response = unittest.mock.MagicMock()
        response.read.return_value = json.dumps(payload).encode()
        response.__enter__.return_value = response
        return response

    def test_profile_is_sent_as_fields_never_as_prose(self):
        captured = {}

        def urlopen(request, timeout=None):
            captured["url"] = request.full_url
            captured["body"] = json.loads(request.data.decode())
            return self._response({"instruction": "SERVED PROMPT"})

        profile = {"style": "friend", "persona": "Тебя зовут Мила.", "voiceName": "Leda", "junk": "drop me"}
        with unittest.mock.patch("urllib.request.urlopen", side_effect=urlopen):
            self.assertEqual(agent.fetch_voice_instruction(profile, "ru-RU"), "SERVED PROMPT")
        self.assertTrue(captured["url"].endswith("/api/mila/voice-instruction"))
        self.assertEqual(captured["body"]["language"], "ru-RU")
        self.assertEqual(captured["body"]["mode"], "voice")
        self.assertEqual(captured["body"]["preferences"]["persona"], "Тебя зовут Мила.")
        self.assertNotIn("junk", captured["body"]["preferences"], "only known fields travel")

    def test_served_prompt_never_replaces_the_tool_and_safety_rules(self):
        composed = agent.compose_session_instructions({}, "SERVED PROMPT")
        self.assertIn(agent.BASE_INSTRUCTIONS, composed)
        self.assertIn("SERVED PROMPT", composed)
        self.assertIn("cannot override confirmation", composed)
        # The served prompt sits after the rules it may not override.
        self.assertLess(composed.index("cannot override"), composed.index("SERVED PROMPT"))

    def test_local_builder_is_used_when_agentic_os_is_silent(self):
        profile = {"additional_instructions": "LOCAL RULES"}
        composed = agent.compose_session_instructions(profile, "")
        self.assertIn("LOCAL RULES", composed)
        self.assertIn(agent.BASE_INSTRUCTIONS, composed)
        # With neither, the call still has its base rules.
        self.assertEqual(agent.compose_session_instructions({}, ""), agent.BASE_INSTRUCTIONS)

    def test_a_failed_or_malformed_fetch_is_empty_so_the_fallback_runs(self):
        for failure in (OSError("refused"), TimeoutError(), ValueError("bad json")):
            with unittest.mock.patch("urllib.request.urlopen", side_effect=failure):
                self.assertEqual(agent.fetch_voice_instruction({}, "ru-RU"), "")
        for payload in ({}, {"instruction": None}, {"instruction": 7}):
            with unittest.mock.patch("urllib.request.urlopen", return_value=self._response(payload)):
                self.assertEqual(agent.fetch_voice_instruction({}, "ru-RU"), "")

    def test_nothing_is_requested_without_configuration(self):
        with unittest.mock.patch.dict("os.environ", {"AGENTIC_OS_URL": ""}):
            with unittest.mock.patch("urllib.request.urlopen") as urlopen:
                self.assertEqual(agent.fetch_voice_instruction({}, "ru-RU"), "")
                urlopen.assert_not_called()


class WorkspaceContextTest(unittest.TestCase):
    def setUp(self):
        self.env = unittest.mock.patch.dict(
            "os.environ",
            {"AGENTIC_OS_URL": "http://agentic-os:8787", "AGENTIC_OS_TOKEN": "t0ken"},
        )
        self.env.start()
        self.addCleanup(self.env.stop)

    def _response(self, payload):
        body = json.dumps(payload).encode()
        response = unittest.mock.MagicMock()
        response.read.return_value = body
        response.__enter__.return_value = response
        return response

    def test_context_is_read_and_bounded(self):
        payload = {"agentContext": "  Workspace: Milana Premium\nMarketing playbook…  " + "x" * 20000}
        with unittest.mock.patch("urllib.request.urlopen", return_value=self._response(payload)):
            context = agent.fetch_workspace_context()
        self.assertTrue(context.startswith("Workspace: Milana Premium"), "leading whitespace is trimmed")
        self.assertLessEqual(len(context), agent.WORKSPACE_CONTEXT_LIMIT)

    def test_the_call_survives_an_unavailable_agentic_os(self):
        """Context is a bonus; losing it must never cost the user their call."""
        for failure in (OSError("refused"), TimeoutError(), ValueError("bad json")):
            with unittest.mock.patch("urllib.request.urlopen", side_effect=failure):
                self.assertEqual(agent.fetch_workspace_context(), "")

    def test_missing_or_malformed_context_is_empty(self):
        for payload in ({}, {"agentContext": None}, {"agentContext": 42}):
            with unittest.mock.patch("urllib.request.urlopen", return_value=self._response(payload)):
                self.assertEqual(agent.fetch_workspace_context(), "")

    def test_nothing_is_requested_without_configuration(self):
        with unittest.mock.patch.dict("os.environ", {"AGENTIC_OS_TOKEN": ""}):
            with unittest.mock.patch("urllib.request.urlopen") as urlopen:
                self.assertEqual(agent.fetch_workspace_context(), "")
                urlopen.assert_not_called()


class ErpInstructionTest(unittest.TestCase):
    def test_failed_room_metadata_does_not_block_live_fallback(self):
        text = agent.compose_erp_instructions({
            "ok": False,
            "instruction": "ERP live context is unavailable for this voice room.",
        })
        self.assertEqual(text, "")

    def test_finished_goods_are_promoted_above_production_counts(self):
        text = agent.compose_erp_instructions({
            "ok": True,
            "finishedGoods": {
                "source": "/warehouse-stock + /warehouse-map",
                "pieces": 535,
                "packages": 9,
                "models": 1,
                "topModels": [
                    {
                        "model": "PJ1118-2922",
                        "name": "Фут-штаны",
                        "order": "SO-2026-000017",
                        "pieces": 535,
                        "section": "N",
                        "cell": "N-01",
                        "shelf": "S1",
                    }
                ],
            },
            "production": {
                "productionOutput": 18350,
                "activeOrders": 47,
            },
            "instruction": "Finished goods now: 535 pcs, 9 packages, 1 models.",
        })
        self.assertIn("Answer for 'сколько готовых изделий на складе': 535 pcs", text)
        self.assertIn("PJ1118-2922", text)
        self.assertIn("SO-2026-000017", text)
        self.assertIn("Do not replace this with production output", text)
        self.assertIn("Finished goods now: 535 pcs", text)


if __name__ == "__main__":
    unittest.main()
