import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("insights_contract", Path(__file__).parents[1] / "verify_insights_contract.py")
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)


class InsightsContractTests(unittest.TestCase):
    def test_only_explicit_temporary_statuses_allow_degraded_release(self):
        for status in (502, 503, 504):
            self.assertIn("unavailable", contract.verify(status, "unused"))
            with self.assertRaises(SystemExit):
                contract.verify(status, "unused", strict=True)
        for status in (301, 401, 403, 404, 429, 500):
            with self.assertRaises(SystemExit):
                contract.verify(status, "unused")

    def test_success_requires_valid_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "payload.json"
            for body in ({}, {"schema": 2}, {"schema": 1, "recommendations": []}):
                path.write_text(json.dumps(body))
                with self.assertRaises(SystemExit):
                    contract.verify(200, path)
            path.write_text("not JSON")
            with self.assertRaises(ValueError):
                contract.verify(200, path)
            path.write_text(json.dumps({"schema": 1, "recommendations": [{"items": [{}]}]}))
            self.assertIn("1 groups", contract.verify(200, path))
