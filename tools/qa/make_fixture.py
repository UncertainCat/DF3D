"""Run a declared synthetic fixture producer and attest its freshly written output."""
from pathlib import Path
import subprocess
import sys
import tempfile
from evidence import ROOT


def main():
    builder, destination = sys.argv[1:]
    executable = ROOT / "build/tools" / (builder + ".exe")
    if not executable.is_file():
        print("QA_INCOMPLETE: missing fixture producer " + str(executable))
        return 77
    output = Path(destination).resolve()
    if not output.is_relative_to((ROOT / "build").resolve()):
        raise ValueError("Generated fixture must stay within build/")
    output.parent.mkdir(parents=True, exist_ok=True)
    # Generate privately so failed producers cannot leave a stale successful file.
    with tempfile.TemporaryDirectory(dir=output.parent, prefix="fixture-") as directory:
        candidate = Path(directory) / output.name
        code = subprocess.run([str(executable), str(candidate)], cwd=ROOT).returncode
        if code: return code
        if not candidate.is_file() or candidate.stat().st_size == 0:
            raise ValueError("Fixture producer returned no data")
        candidate.replace(output)
    print("QA_FIXTURE_PASS " + output.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
