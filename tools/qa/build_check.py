"""Small build wrapper: a completion marker is emitted only after CMake succeeds."""
import subprocess
import sys

code = subprocess.call(["cmake", "--build", sys.argv[1], "--parallel", "4"])
if code == 0:
    print("QA_BUILD_PASS", flush=True)
raise SystemExit(code)
