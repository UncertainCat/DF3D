import copy
import re
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from catalog import load_catalog, validate_catalog, ordered_checks
from verify import check_environment, command_for, optional_readiness, recorded_location_catalog_ready


class CatalogTests(unittest.TestCase):
    def test_windows_powershell_does_not_inherit_pwsh_modules(self):
        env = {"PATH": "runtime", "PSModulePath": "PowerShell7/Modules", "KEEP": "value"}
        with patch("verify.powershell_executable", return_value="C:/Windows/powershell.exe"):
            self.assertEqual(check_environment({"kind": "powershell"}, env),
                             {"PATH": "runtime", "KEEP": "value"})
            self.assertNotIn("PSMODULEPATH", check_environment(
                {"kind": "powershell"}, {"PSMODULEPATH": "PowerShell7/Modules"}))
        with patch("verify.powershell_executable", return_value="C:/Program Files/PowerShell/pwsh.exe"):
            self.assertEqual(check_environment({"kind": "powershell"}, env), env)
        self.assertEqual(check_environment({"kind": "godot"}, env), env)
        self.assertEqual(env["PSModulePath"], "PowerShell7/Modules")

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.path = "presentations/godot/project/tests/sample_test.gd"
        script = self.root / self.path
        script.parent.mkdir(parents=True)
        script.write_text("extends SceneTree\n")
        self.row = dict(id="sample", lane="core", kind="godot",
                        script="res://tests/sample_test.gd", completion="^PASS$",
                        prerequisites=["extension_build"])
        self.data = dict(version=1, lanes={"core": "offline", "gpu": "renderer", "live": "owned"},
                         checks=[self.row], exclusions=[])

    def validate(self):
        return validate_catalog(self.data, self.root)

    def test_new_and_removed_scripts_require_inventory_changes(self):
        self.validate()
        extra = self.root / "presentations/godot/project/tests/new_probe.gd"
        extra.write_text("extends SceneTree\n")
        with self.assertRaisesRegex(ValueError, "Unclassified"):
            self.validate()
        self.data["exclusions"] = [dict(path=extra.relative_to(self.root).as_posix(), status="manual", reason="Requires a protected authoritative target.")]
        self.validate()
        extra.unlink()
        with self.assertRaisesRegex(ValueError, "Stale"):
            self.validate()

    def test_exclusions_cannot_hide_active_checks_or_omit_reason(self):
        self.data["exclusions"] = [dict(path=self.path, status="manual", reason="not applicable")]
        with self.assertRaisesRegex(ValueError, "actively covered"):
            self.validate()
        self.data["checks"] = []
        self.data["exclusions"][0]["reason"] = " "
        with self.assertRaisesRegex(ValueError, "reason"):
            self.validate()

    def test_retirement_requires_a_real_replacement(self):
        alias = self.root / "presentations/godot/project/tests/old_test.gd"
        alias.write_text('extends "res://tests/sample_test.gd"\n')
        row = dict(path=alias.relative_to(self.root).as_posix(), status="retired", reason="Replaced by semantic test.")
        self.data["exclusions"] = [row]
        with self.assertRaisesRegex(ValueError, "replacement"):
            self.validate()
        row["replacement"] = "sample"
        self.validate()

    def test_unknown_and_cyclic_prerequisites_fail_even_unselected(self):
        self.row["prerequisites"] += ["extensoin_build"]
        with self.assertRaisesRegex(ValueError, "Unknown QA prerequisite"):
            self.validate()
        self.row["prerequisites"] = ["extension_build", "sample"]
        with self.assertRaisesRegex(ValueError, "Cyclic"):
            self.validate()

    def test_dependency_order_is_independent_of_manifest_order(self):
        rows = [dict(id="consumer", prerequisites=["fixture"]), dict(id="fixture", prerequisites=["root_build"])]
        self.assertEqual([r["id"] for r in ordered_checks(rows, {"consumer"})], ["fixture", "consumer"])

    def test_missing_and_escaping_source_paths_fail(self):
        self.row["script"] = "res://tests/missing.gd"
        with self.assertRaisesRegex(ValueError, "Missing QA source"):
            self.validate()
        self.row["script"] = "res://tests/../../other.gd"
        with self.assertRaisesRegex(ValueError, "relative"):
            self.validate()

    def test_same_script_environment_matrix_is_active_coverage(self):
        self.data["checks"].append(dict(self.row, id="sample_enabled", environment={"DF3D_FRAME_BOUNDARIES": "1"}))
        self.validate()
        self.data["checks"][1]["environment"] = {"PATH": "unsafe"}
        with self.assertRaisesRegex(ValueError, "environment"):
            self.validate()

    def test_python_discovery_uses_actual_runner_directory(self):
        script = self.root / "tools/checks/test_new.py"
        script.parent.mkdir(parents=True)
        script.write_text("import unittest\n")
        with self.assertRaisesRegex(ValueError, "Unclassified"):
            self.validate()
        self.data["checks"].append(dict(id="python", lane="core", kind="python", completion="^OK$", prerequisites=[],
                                       command=["-m", "unittest", "discover", "-s", "tools/checks", "-p", "test_*.py"]))
        self.validate()

    def test_per_check_environment_isolated_and_expanded(self):
        env = {"PATH": "tools", "DF3D_DF_PATH": "assets", "DF3D_GODOT": "engine", "DF3D_FIXTURE": "live", "DF3D_PROFILE": "deep"}
        spec = dict(kind="godot", environment={"DF3D_PROFILE": "off", "DF3D_FIXTURE": "{output}/test.df3dfix"})
        actual = check_environment(spec, env, Path("fresh"))
        self.assertEqual(actual["DF3D_PROFILE"], "off")
        self.assertEqual(actual["DF3D_FIXTURE"], "fresh/test.df3dfix")
        self.assertEqual(env["DF3D_PROFILE"], "deep")
        self.assertNotIn("DF3D_FIXTURE", check_environment(dict(kind="godot"), env))

    def test_python_nested_nonpackage_is_not_counted_as_discovered(self):
        directory = self.root / "tools/checks/nested"
        directory.mkdir(parents=True)
        (directory / "test_hidden.py").write_text("import unittest\n")
        self.data["checks"].append(dict(id="python", lane="core", kind="python", completion="^OK$", prerequisites=[],
                                       command=["-m", "unittest", "discover", "-s", "tools/checks", "-p", "test_*.py"]))
        with self.assertRaisesRegex(ValueError, "Unclassified.*test_hidden"):
            self.validate()
        (directory / "__init__.py").write_text("")
        self.validate()

    def test_missing_python_dependency_reports_not_ready(self):
        with patch("verify.subprocess.run", side_effect=OSError("missing interpreter")):
            ready = optional_readiness("missing", "missing", {"PATH": ""})
        self.assertFalse(ready["python_lupa"])

    def test_location_capture_requires_both_recordings_and_provenance(self):
        directory = self.root / "build/notes/pm/location-render-source"
        directory.mkdir(parents=True)
        names = ("location-transport-comparison.json", "native-location-metadata.json",
                 "native-location-scroll.json", "native-location-scroll-art.json", "native-location-scroll-states.json", "native-list-scroll.json", "provenance.txt")
        with patch("verify.ROOT", self.root):
            self.assertFalse(recorded_location_catalog_ready())
            for name in names:
                (directory / name).write_text("fixture")
            self.assertTrue(recorded_location_catalog_ready())
            for name in names:
                (directory / name).unlink()
                self.assertFalse(recorded_location_catalog_ready())
                (directory / name).write_text("fixture")

    def test_registered_profiling_matrix_uses_supported_modes_and_private_outputs(self):
        rows = [row for row in load_catalog()["checks"]
                if row.get("script") == "res://tests/profiling_mode_test.gd"]
        self.assertEqual(len(rows), 3)
        self.assertEqual({row["environment"]["DF3D_PROFILE"] for row in rows}, {"off", "basic", "deep"})
        outputs = set()
        for row in rows:
            env = row["environment"]
            self.assertIsNotNone(re.fullmatch(row["completion"], "PROFILING_MODE_PASS " + env["DF3D_PROFILE"]))
            self.assertTrue(env["DF3D_PROFILE_OUT"].startswith("{output}/"))
            outputs.add(env["DF3D_PROFILE_OUT"])
        self.assertEqual(len(outputs), len(rows))


if __name__ == "__main__":
    unittest.main()
