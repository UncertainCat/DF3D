import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from bake_widgets import bake


class BakeTests(unittest.TestCase):
    def setUp(self):
        self.capture = {"format_version": 1, "df_version": "test",
            "coordinate_space": "native_widget_rect_inclusive", "roots": [
                {"id": "info/0", "native_type": "widget_text", "name": "Name",
                 "text": "A specific dwarf from a captured fortress", "rect": [10, 4, 19, 5],
                 "custom": {"render": 1}, "children": []}]}
        self.recipe = {"format_version": 1, "df_version": "test", "id": "example",
            "pixel_scale": [8, 12], "origin": [10, 4], "widgets": {"info/0": {
                "expected_type": "widget_text", "expected_name": "Name", "id": "name",
                "type": "label", "binding": "selection.title"}}}

    def test_geometry_and_dynamic_data_are_separate(self):
        result = bake(self.capture, self.recipe)
        self.assertEqual(result["nodes"][0]["rect"], [0, 0, 80, 24])
        self.assertNotIn("text", result["nodes"][0])
        self.assertNotIn("specific dwarf", str(result))
        self.assertIn("custom callbacks", result["unsupported_widgets"][0]["reason"])

    def test_unknown_nodes_are_not_guessed(self):
        self.recipe["widgets"] = {}
        result = bake(self.capture, self.recipe)
        self.assertEqual(result["nodes"], [])
        self.assertEqual(len(result["unsupported_widgets"]), 1)

    def test_stale_identity_and_versions_fail(self):
        for field, value in [("name", "Different"), ("native_type", "widget_table")]:
            capture = copy.deepcopy(self.capture)
            capture["roots"][0][field] = value
            with self.assertRaises(ValueError): bake(capture, self.recipe)
        self.capture["df_version"] = "new"
        with self.assertRaises(ValueError): bake(self.capture, self.recipe)

    def test_unsafe_or_incomplete_mapping_fails(self):
        for update in [{"type": "script"}, {"text": "captured name"}, {"type": "button"}]:
            recipe = copy.deepcopy(self.recipe)
            recipe["widgets"]["info/0"].update(update)
            with self.assertRaises(ValueError): bake(self.capture, recipe)
        self.capture["roots"][0]["rect"][0] = float("nan")
        with self.assertRaises(ValueError): bake(self.capture, self.recipe)

    def test_cli_preserves_existing_edited_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            capture, recipe, output = (root/name for name in ("capture.json", "recipe.json", "edited.json"))
            capture.write_text(json.dumps(self.capture), encoding="utf-8")
            recipe.write_text(json.dumps(self.recipe), encoding="utf-8")
            output.write_text("hand-edited product", encoding="utf-8")
            run = subprocess.run([sys.executable, str(Path(__file__).with_name("bake_widgets.py")),
                                  str(capture), str(recipe), str(output)], capture_output=True)
            self.assertNotEqual(run.returncode, 0)
            self.assertEqual(output.read_text(encoding="utf-8"), "hand-edited product")


if __name__ == "__main__": unittest.main()
