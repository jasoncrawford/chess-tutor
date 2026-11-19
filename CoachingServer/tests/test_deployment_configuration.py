import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class DeploymentConfigurationTests(unittest.TestCase):
    def test_vercel_uses_supported_python_runtime_selection(self):
        configuration = json.loads((ROOT / "vercel.json").read_text(encoding="utf-8"))

        for function in configuration.get("functions", {}).values():
            self.assertNotIn("runtime", function)
        self.assertEqual("3.12", (ROOT / ".python-version").read_text(encoding="utf-8").strip())


if __name__ == "__main__":
    unittest.main()
