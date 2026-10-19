"""Compile and exercise launcher ownership with harmless Windows process stand-ins."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    compiler = Path(os.environ.get("WINDIR", "")) / "Microsoft.NET/Framework64/v4.0.30319/csc.exe"
    if os.name != "nt" or not compiler.is_file():
        print("Windows .NET Framework compiler is required")
        raise SystemExit(77)
    with tempfile.TemporaryDirectory(prefix="df3d-lifecycle-") as temporary:
        directory = Path(temporary)
        executable = directory / "lifecycle-tests.exe"
        references = ["System.Windows.Forms", "System.Drawing", "System.Web.Extensions",
                      "System.IO.Compression", "System.IO.Compression.FileSystem"]
        subprocess.run([str(compiler), "/nologo", "/target:winexe", "/platform:x64",
                        "/main:LifecycleTests", f"/out:{executable}",
                        *[f"/reference:{name}.dll" for name in references],
                        str(ROOT / "tools/release/Launcher.cs"),
                        str(ROOT / "tools/release/LifecycleTests.cs")], check=True)
        report = directory / "result.txt"
        result = subprocess.run([str(executable), "--test", str(report)], timeout=40)
        print(report.read_text() if report.exists() else "Lifecycle test did not produce a result")
        result.check_returncode()


if __name__ == "__main__":
    main()
