import json
from pathlib import Path
import socket
import struct
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest

from render_profile_collector import Collector, Framer, ProtocolError, decode, encode, packet, render_summary, run, visual_frame


def frame(number):
    return [number, 12, "Frame Begin", 0.0, 0.0, "Geometry", 1.0, 2.0,
            "Lighting", 3.0, 5.0, "Frame End", 4.0, 7.0]


class RenderCollectorTests(unittest.TestCase):
    def test_known_command_bytes_and_roundtrip(self):
        command = ["profiler:visual", 1, [True]]
        data = encode(command)
        self.assertEqual(data[:8], struct.pack("<II", 28, 3))
        self.assertEqual(decode(data), command)
        self.assertEqual(decode(encode([None, -3, 2**42, 1.125, "héllo", False])),
                         [None, -3, 2**42, 1.125, "héllo", False])

    def test_fragmented_packets_and_limits(self):
        wire = packet(["a", 1, []]) + packet(["b", 1, [2]])
        framer, values = Framer(), []
        for byte in wire:
            values.extend(decode(payload) for payload in framer.feed(bytes([byte])))
        self.assertEqual(values, [["a", 1, []], ["b", 1, [2]]])
        with self.assertRaises(ProtocolError):
            list(Framer().feed(struct.pack("<I", 100000000)))
        with self.assertRaises(ProtocolError):
            decode(encode([1])[:-1])
        with self.assertRaises(ProtocolError):
            decode(encode([1]) + b"extra")

    def test_timestamp_differences_not_sum(self):
        sample = visual_frame(frame(20))
        self.assertEqual(sample["cpu_ms"], 4.0)
        self.assertEqual(sample["gpu_ms"], 7.0)
        self.assertEqual(sample["stages"]["Geometry"], {"cpu_ms": 2.0, "gpu_ms": 3.0})
        self.assertEqual(sum(value["gpu_ms"] for value in sample["stages"].values()), 7.0)
        bad = frame(20)
        bad[9] = -1.0
        with self.assertRaises(ProtocolError):
            visual_frame(bad)

    def test_hierarchy_intervals_are_exclusive(self):
        data = [4, 15, "Frame Begin", 0, 0, ">Scene", 1, 1, "Geometry", 2, 2,
                "<Scene", 4, 4, "Frame End", 5, 5]
        sample = visual_frame(data)
        self.assertEqual(sample["stages"]["Scene/Geometry"]["cpu_ms"], 2)
        self.assertEqual(sample["stages"]["<after Scene>"]["cpu_ms"], 1)
        self.assertEqual(sum(value["cpu_ms"] for value in sample["stages"].values()), 5)

    def test_phase_guards_late_frames_duplicates_and_retention(self):
        collector = Collector(limit=3, edge_guard=2)
        collector.message(["df3d:render_phase", 1, ["free", "start", 10]])
        for number in range(10, 20):
            collector.message(["visual:profile_frame", 1, frame(number)])
        collector.message(["visual:profile_frame", 1, frame(19)])
        collector.message(["df3d:render_phase", 1, ["free", "end", 25]])
        collector.message(["visual:profile_frame", 1, frame(22)])
        collector.message(["visual:profile_frame", 1, frame(23)])
        phase = collector.summary()["phases"][0]
        self.assertEqual(phase["retained_frames"], 3)
        self.assertEqual(phase["last_retained_frame"], 22)
        self.assertEqual(collector.counts["duplicate_frames"], 1)
        self.assertGreater(phase["dropped_by_limit"], 0)
        self.assertNotIn("samples", phase)
        self.assertLessEqual(len(phase["outliers"]), 3)

    def test_summary_is_bounded_and_not_raw_frames(self):
        collector = Collector(edge_guard=0)
        collector.message(["df3d:render_phase", 1, ["free", "start", 10]])
        collector.message(["visual:profile_frame", 1, frame(15)])
        collector.message(["df3d:render_phase", 1, ["free", "end", 20]])
        result = collector.summary()
        result["phases"] *= 20
        text = render_summary(result)
        self.assertLess(len(text.splitlines()), 25)
        self.assertIn("CPU mean/p95 4.000/4.000", text)
        self.assertIn("17 further phases", text)
        self.assertNotIn("outliers", text)

    def test_network_enable_message_and_output_on_close(self):
        with tempfile.TemporaryDirectory() as folder:
            args = SimpleNamespace(ready=Path(folder)/"ready.json", output=Path(folder)/"output.json",
                                   max_frames=8, edge_guard=1, timeout=5)
            codes = []
            thread = threading.Thread(target=lambda: codes.append(run(args)))
            thread.start()
            deadline = time.monotonic() + 2
            while not args.ready.exists() and time.monotonic() < deadline:
                time.sleep(.01)
            port = json.loads(args.ready.read_text())["port"]
            with socket.create_connection(("127.0.0.1", port), timeout=2) as connection:
                framer = Framer()
                messages = []
                while not messages:
                    messages.extend(decode(payload) for payload in framer.feed(connection.recv(1024)))
                self.assertEqual(messages, [["profiler:visual", 1, [True]]])
                for message in [["df3d:render_phase", 1, ["free", "start", 10]],
                                ["visual:profile_frame", 1, frame(14)],
                                ["df3d:render_phase", 1, ["free", "end", 20]]]:
                    connection.sendall(packet(message))
            thread.join(3)
            self.assertFalse(thread.is_alive())
            self.assertEqual(codes, [0])
            result = json.loads(args.output.read_text())
            self.assertEqual(result["status"], "complete")
            self.assertEqual(result["phases"][0]["retained_frames"], 1)

    def test_network_malformed_packet_has_error_output(self):
        with tempfile.TemporaryDirectory() as folder:
            args = SimpleNamespace(ready=Path(folder)/"ready.json", output=Path(folder)/"output.json",
                                   max_frames=8, edge_guard=1, timeout=5)
            codes = []
            thread = threading.Thread(target=lambda: codes.append(run(args)))
            thread.start()
            deadline = time.monotonic() + 2
            while not args.ready.exists() and time.monotonic() < deadline:
                time.sleep(.01)
            with socket.create_connection(("127.0.0.1", json.loads(args.ready.read_text())["port"])) as connection:
                connection.sendall(struct.pack("<I", 0xffffffff))
            thread.join(3)
            self.assertEqual(codes, [1])
            result = json.loads(args.output.read_text())
            self.assertEqual(result["status"], "error")
            self.assertTrue(result["errors"])


if __name__ == "__main__":
    unittest.main()
