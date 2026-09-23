import os
from pathlib import Path
import sys
import tempfile
import unittest
from evidence import checks, classify, evaluate, execute, overall_status, EXIT_CODES
from verify import command_for


class EvidenceTests(unittest.TestCase):
    def test_success_requires_completion(self):
        spec = {"completion": "^TEST_PASS$"}
        for code, output in [(0,""),(1,"TEST_PASS\n"),(0,"NOT_TEST_PASS\n")]:
            self.assertTrue(evaluate(spec,code,output))
        self.assertFalse(evaluate(spec,0,"TEST_PASS\n"))

    def test_engine_error_is_not_success(self):
        for error in ["ERROR: empty image"," SCRIPT ERROR: bad type","FAIL: assertion"]:
            self.assertTrue(evaluate({"completion":"TEST_PASS"},0,error+"\nTEST_PASS\n"))

    def test_probe_results_are_evidence_not_exit_codes(self):
        spec = {"completion":"DONE","observations":1}
        for value in ['{"case":"a","bug":true}','{}','[]','null',
                      '{"case":[],"bug":false}','{"case":"a","bug":0}','not json']:
            self.assertTrue(evaluate(spec,0,"QA_PROBE "+value+"\nDONE"))
        self.assertTrue(evaluate(spec,0,"DONE"))
        self.assertFalse(evaluate(spec,0,'QA_PROBE {"case":"a","bug":false}\nDONE'))
        duplicate = 'QA_PROBE {"case":"a","bug":false}\n' * 2 + 'DONE'
        self.assertTrue(evaluate(dict(spec,observations=2),0,duplicate))

    def test_explicit_incomplete_is_not_failure_or_success(self):
        spec={"completion":"PASS"}
        self.assertEqual(classify(spec,77,"QA_INCOMPLETE: unavailable\n")[0],"incomplete")
        self.assertEqual(classify(spec,77,"unavailable\n")[0],"failed")
        self.assertEqual(classify(spec,77,"ERROR: bug\nQA_INCOMPLETE: unavailable\n")[0],"failed")
        self.assertEqual(classify(spec,0,"QA_INCOMPLETE: unavailable\n")[0],"failed")
        self.assertEqual(classify(spec,0,"QA_INCOMPLETE: unavailable\nPASS\n")[0],"failed")

    def test_execute_records_real_completion_timeout_and_unavailable_tool(self):
        with tempfile.TemporaryDirectory() as directory:
            spec={"id":"test","completion":"^PASS$","timeout":5}
            def run(code, **overrides):
                return execute(dict(spec,**overrides),[sys.executable,"-c",code],env=os.environ.copy(),output_dir=directory)
            passed=run("print('PASS')")
            self.assertEqual(passed["status"],"passed")
            self.assertIn("command",passed)
            self.assertTrue(Path(passed["log"]).is_file())
            self.assertEqual(run("print('nothing')")["status"],"failed")
            self.assertEqual(run("print('QA_INCOMPLETE: missing');exit(77)")["status"],"incomplete")
            timed=run("import time;time.sleep(5)",timeout=0.05)
            self.assertEqual(timed["exit"],"timeout")
            self.assertEqual(timed["status"],"failed")
            absent=execute(spec,[str(Path(directory)/"absent.exe")],env=os.environ.copy(),output_dir=directory)
            self.assertEqual(absent["status"],"incomplete")

    def test_surviving_process_tree_is_recorded_as_failure_not_abort(self):
        # A second TimeoutExpired (tree survives taskkill) used to escape execute().
        from unittest.mock import patch
        import subprocess as sp
        class Stuck:
            pid = 4242
            def wait(self, timeout=None):
                raise sp.TimeoutExpired("stuck", timeout)
        with tempfile.TemporaryDirectory() as directory,              patch("evidence.subprocess.Popen", return_value=Stuck()),              patch("evidence.subprocess.run", return_value=None),              patch("evidence.os.killpg", create=True, return_value=None):
            row = execute({"id":"stuck","completion":"^PASS$","timeout":0.01},["ignored"],env=os.environ.copy(),output_dir=directory)
        self.assertEqual(row["status"], "failed")
        self.assertEqual(row["exit"], "timeout")
        self.assertTrue(any("did not stop" in reason for reason in row["reasons"]))

    def test_run_dir_pruning_keeps_newest_and_named_outputs(self):
        from verify import prune_run_dirs, RUN_DIR_PATTERN
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            names = [f"2026010{i // 10}-00000{i % 10}-000000" for i in range(15)]
            for name in names + ["final-gpu", "anchor", "not-a-run"]:
                (base / name).mkdir()
                (base / name / "summary.json").write_text("{}")
            (base / "extension_build.json").write_text("{}")
            current = base / names[-1]
            removed = prune_run_dirs(base, current, keep=10)
            self.assertEqual([p.name for p in removed], names[:5])
            self.assertTrue(current.is_dir())
            remaining = sorted(p.name for p in base.iterdir())
            self.assertEqual([n for n in remaining if RUN_DIR_PATTERN.match(n)], names[5:])
            for kept in ["final-gpu", "anchor", "not-a-run", "extension_build.json"]:
                self.assertTrue((base / kept).exists(), kept)
            # A user-named output under build/qa is never a candidate, and pruning is idempotent.
            self.assertEqual(prune_run_dirs(base, base / "final-gpu", keep=10), [])
            self.assertEqual(prune_run_dirs(base / "missing", current), [])

    def test_ctest_listing_failure_degrades_to_binary_products(self):
        from unittest.mock import patch
        import verify
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / "worldmodel_tests.exe"
            binary.write_bytes(b"x")
            with patch("verify.subprocess.check_output", side_effect=OSError("no ctest")):
                products = verify.products("root_build", binary, env={"PATH": directory})
        self.assertIn(str(binary.resolve()), products)

    def test_result_precedence_and_exit_codes(self):
        def result(*statuses):
            return overall_status([{"status": s} for s in statuses])
        self.assertEqual(result("passed"), "passed")
        self.assertEqual(result("passed", "passed_with_known_issues"), "passed_with_known_issues")
        self.assertEqual(EXIT_CODES[result("passed_with_known_issues")], 0)
        self.assertEqual(result("passed_with_known_issues", "incomplete"), "incomplete")
        self.assertEqual(result("passed_with_known_issues", "failed", "incomplete"), "failed")
        self.assertEqual(result(), "incomplete")

    def test_known_issue_status_reaches_gate_report_and_allows_dependent_check(self):
        import contextlib
        import io
        import json
        from unittest.mock import patch
        import verify
        from test_diagnostics import BANNER, FONT
        # Real subprocesses exercise the runner without reprobeing Godot.
        rows = [dict(id="known", lane="core", kind="python", completion="^PASS$",
                     prerequisites=[], command=["-c", "print(" + repr(BANNER + FONT + "PASS") + ")"]),
                dict(id="dependent", lane="core", kind="python", completion="^PASS$",
                     prerequisites=["known"], command=["-c", "print('PASS')"])]
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "evidence"
            console = io.StringIO()
            with patch.object(sys, "argv", ["verify.py", "--lane", "core", "--output", str(out)]), \
                 patch.object(verify, "checks", return_value=rows), \
                 patch.object(verify, "load_catalog", return_value={"checks": rows, "exclusions": []}), \
                 patch.object(verify, "source_identity", return_value={"test": "unchanged"}), \
                 patch.object(verify, "optional_readiness", return_value={}), \
                 contextlib.redirect_stdout(console):
                self.assertEqual(verify.main(), 0)
            report = json.loads((out / "summary.json").read_text())
            self.assertEqual(report["status"], "passed_with_known_issues")
            self.assertEqual([r["status"] for r in report["results"]], ["passed_with_known_issues", "passed"])
            self.assertEqual(report["results"][0]["diagnostics"]["known_engine"][0]["count"], 1)
            self.assertIn(FONT, Path(report["results"][0]["log"]).read_text())
            self.assertIn("QA PASSED (KNOWN ISSUES)", console.getvalue())
            self.assertNotIn("FAILED", console.getvalue())

    def test_manifest_and_native_argument_boundaries(self):
        from verify import check_environment
        env = {"DF3D_DF_PATH": "installed", "PATH": "tools"}
        self.assertNotIn("DF3D_DF_PATH", check_environment({"kind": "ctest"}, env))
        self.assertEqual(check_environment({"kind": "godot"}, env), env)
        catalog=checks()
        spec=next(c for c in catalog if c["id"]=="management_lua_contract_tests")
        command=command_for(spec,godot="unused",df_path="C:/DF install with spaces",output=Path("unused"))
        self.assertEqual(command[1],"C:/DF install with spaces/hack/lua53.dll")
        self.assertEqual(len(command),2)
        adapter=next(c for c in catalog if c["id"]=="management_contract_test")
        self.assertEqual(adapter["lane"],"core")
        self.assertNotIn("df_assets",adapter["prerequisites"])
        self.assertIn("root_build",adapter["prerequisites"])
        self.assertIn("extension_build",adapter["prerequisites"])


if __name__ == "__main__":
    unittest.main()
