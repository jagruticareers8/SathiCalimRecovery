import unittest
from main import detect_intent, execute_demo_tool, local_answer

class AgentRuleTests(unittest.TestCase):
    def test_hinglish_rejection(self):
        self.assertEqual(detect_intent("Mera claim reject ho gaya, ab kya karu?"), "explain_rejection")

    def test_hinglish_documents(self):
        self.assertEqual(detect_intent("Kaun se documents chahiye?"), "required_documents")

    def test_hindi_status(self):
        self.assertEqual(detect_intent("मेरा क्लेम स्टेटस क्या है"), "claim_status")

    def test_tool_does_not_submit_claim(self):
        result = execute_demo_tool("prepare_reconsideration_draft")
        self.assertIn("has not been sent", result["warning"])

    def test_local_answer_marks_demo(self):
        result = local_answer("claim reject kyun hua", "hinglish")
        self.assertEqual(result["intent"], "explain_rejection")
        self.assertEqual(result["mode"], "local_rules")

if __name__ == "__main__":
    unittest.main()
