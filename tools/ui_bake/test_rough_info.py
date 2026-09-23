import json
import tempfile
import unittest
from pathlib import Path

from rough_info import GROUPS, inventory, page


class RoughImportTests(unittest.TestCase):
    def test_values_and_callbacks_are_not_product_data(self):
        capture = {"cell_pixels": [8, 12], "roots": [{
            "id": "body", "rect": [10, 10, 20, 20],
            "native_type": "widget_container", "children": [
                {"id": "private", "rect": [11, 11, 12, 12],
                 "native_type": "widget_text", "name": "Private dwarf name",
                 "text": "Fortress secret", "callback": "danger()"},
                {"id": "header", "rect": [11, 11, 12, 12],
                 "native_type": "widget_text", "name": "Name"},
                {"id": "row", "rect": [11, 12, 12, 13],
                 "native_type": "widget_rows", "row_template": True},
                {"id": "bad", "rect": [10, 10, 9, 9]}]}]}
        result = page(capture, "Creatures")
        encoded = json.dumps(result)
        for value in ["Private dwarf name", "Fortress secret", "danger()"]:
            self.assertNotIn(value, encoded)
        nodes = {node["id"]: node for node in result["nodes"]}
        self.assertEqual(nodes["header"]["text"], "Name")
        self.assertEqual(nodes["header"]["rect"], [8, 12, 16, 24])
        self.assertTrue(nodes["row"]["repeat_template"])
        self.assertNotIn("bad", nodes)

    def test_unexposed_body_stays_blank(self):
        result = page({"roots": [{"id": "info"}]}, "Tasks")
        self.assertEqual(result["nodes"], [])
        self.assertIn("deliberately blank", result["remaining"][0])

    def test_inventory_follows_inheritance_and_rejects_cycles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "types.xml").write_text('''<data-definition>
              <class-type type-name="widget"/>
              <class-type type-name="widget_text" inherits-from="widget"/>
              <class-type type-name="special" inherits-from="widget_text"/>
              <class-type type-name="cycle" inherits-from="cycle"/>
              <class-type type-name="unrelated"/>
            </data-definition>''', encoding="utf-8")
            self.assertEqual({entry["native_type"] for entry in inventory(root)},
                             {"widget", "widget_text", "special"})

    def test_destination_tally(self):
        self.assertEqual(sum(max(1, len(tabs)) for tabs in GROUPS.values()), 27)


if __name__ == "__main__":
    unittest.main()
