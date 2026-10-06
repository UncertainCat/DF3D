import struct
import tempfile
import unittest
from pathlib import Path

from expand_fixtures import validate_schema


def snapshot(version):
    # Minimal FlatBuffer table containing the explicit schema_version field.
    payload = struct.pack("<IHHHHiI", 12, 6, 8, 4, 0, 8, version)
    return struct.pack("<I", len(payload)) + payload


class RecordedFixtureTests(unittest.TestCase):
    def test_schema_checks_every_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.df3dfix"
            path.write_bytes(b"DF3DFIX1" + snapshot(11) + snapshot(11))
            validate_schema(path, 11)
            path.write_bytes(b"DF3DFIX1" + snapshot(11) + snapshot(7))
            with self.assertRaisesRegex(ValueError, "snapshot 1: schema 7, expected 11"):
                validate_schema(path, 11)

    def test_empty_and_truncated_recordings_are_not_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.df3dfix"
            for contents in [b"", b"DF3DFIX1", b"DF3DFIX1" + snapshot(11)[:-1]]:
                path.write_bytes(contents)
                with self.assertRaises(ValueError):
                    validate_schema(path, 11)


if __name__ == "__main__":
    unittest.main()
