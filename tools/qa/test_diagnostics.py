import unittest
from diagnostics import console_summary, error_summary
from evidence import classify

BANNER = "Godot Engine v4.7.2.stable.steam.ed1daf0bf - https://godotengine.org\n"
FONT = ('ERROR: Condition "p_image.is_null() || p_image->is_empty()" is true.\n'
        '   at: _texture_2d_update (servers/rendering/renderer_rd/storage_rd/texture_storage.cpp:1617)\n')

class DiagnosticTests(unittest.TestCase):
    def test_known_only_pass_is_distinct_and_keeps_occurrence_counts(self):
        text = BANNER + FONT * 400 + "PASS\n"
        diagnostics = error_summary(text)
        self.assertEqual(diagnostics["known_engine"][0]["count"], 400)
        self.assertEqual(diagnostics["unclassified"], [])
        status, reasons = classify({"completion": "PASS"}, 0, text)
        self.assertEqual(status, "passed_with_known_issues")
        self.assertEqual(reasons, [])
        report = console_summary(dict(id="probe", status=status, reasons=reasons, diagnostics=diagnostics, log="raw.log"))
        self.assertIn("godot-font-atlas x400", report)
        self.assertNotIn("p_image", report)
        self.assertIn("PASSED (KNOWN ISSUES)", report)
        self.assertIn("raw.log", report)

    def test_changed_version_callsite_or_missing_context_stays_unclassified(self):
        for text in (FONT, BANNER.replace("4.7.2", "4.8") + FONT,
                     BANNER.replace("ed1daf0bf", "different") + FONT,
                     BANNER.replace("steam.ed1daf0bf", "custom.different") + FONT,
                     BANNER.replace("ed1daf0bf", "ed1daf0bf-custom") + FONT,
                     BANNER + FONT.replace(":1617)", ":9999)"),
                     BANNER + FONT.replace("_texture_2d_update (", "application_upload ("),
                     BANNER + FONT.splitlines()[0]):
            self.assertEqual(error_summary(text)["known_engine"], [])
            self.assertTrue(error_summary(text)["unclassified"])
            self.assertEqual(classify({"completion": "^PASS$"}, 0, text + "\nPASS\n")[0], "failed")

    def test_dummy_mesh_accepts_only_observed_callsite(self):
        diagnostic = ('ERROR: Parameter "m" is null.\n'
                      ' at: mesh_get_surface_count (servers/rendering/dummy/storage/mesh_storage.h:151)\n')
        self.assertEqual(classify({"completion": "^PASS$"}, 0, BANNER + diagnostic + "PASS\n")[0],
                         "passed_with_known_issues")
        for changed in (diagnostic.replace("mesh_get_surface_count", "mesh_unseen_new_callsite"),
                        diagnostic.replace(":151)", ":9999)")):
            self.assertEqual(classify({"completion": "^PASS$"}, 0, BANNER + changed + "PASS\n")[0], "failed")

    def test_second_engine_banner_cannot_borrow_first_build_identity(self):
        text = BANNER + FONT + BANNER.replace("ed1daf0bf", "different") + FONT + "PASS\n"
        self.assertEqual(error_summary(text)["known_engine"][0]["count"], 1)
        self.assertEqual(len(error_summary(text)["unclassified"]), 1)
        self.assertEqual(classify({"completion": "^PASS$"}, 0, text)[0], "failed")

    def test_known_issues_cannot_hide_failed_process_or_evidence(self):
        spec = {"completion": "^PASS$"}
        for code, suffix in [(1, "PASS\n"), ("timeout", "PASS\n"),
                             (0, ""), (0, "SCRIPT ERROR: Assertion failed.\nPASS\n"),
                             (0, "ERROR: generic RID leak\nPASS\n")]:
            self.assertEqual(classify(spec, code, BANNER + FONT + suffix)[0], "failed")
        self.assertEqual(classify(dict(spec, observations=1), 0,
                         BANNER + FONT + 'QA_PROBE {"case":"a","bug":true}\nPASS\n')[0], "failed")
        self.assertEqual(classify(spec, 77, BANNER + FONT + "QA_INCOMPLETE: unavailable\n")[0], "incomplete")

    def test_unexpected_errors_are_prominent_and_not_hidden_by_known_ones(self):
        text = BANNER + FONT + "SCRIPT ERROR: new bug\n" * 2
        diagnostics = error_summary(text)
        row = dict(id="mixed", status="failed", diagnostics=diagnostics,
                   reasons=["expected completion marker missing"])
        summary = console_summary(row)
        self.assertLess(summary.index("new bug"), summary.index("deferred"))
        self.assertIn("x2", summary)
        self.assertIn("completion marker missing", summary)

    def test_no_diagnostics_or_prerequisite_failure(self):
        self.assertEqual(console_summary(dict(id="ok", status="passed")), "ok: PASSED")
        self.assertIn("missing compiler", console_summary(dict(id="build", status="incomplete", reasons=["missing compiler"])))

if __name__ == "__main__":
    unittest.main()
