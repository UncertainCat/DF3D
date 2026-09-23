"""Collect stock Godot's visual debugger profiler through a loopback TCP peer.

Protocol verified against godotengine/godot ed1daf0bf:
core/debugger/remote_debugger_peer.cpp, remote_debugger.cpp;
servers/debugger/servers_debugger.cpp; core/io/marshalls.cpp.
Only visual profiling is enabled. CPU timestamps are elapsed render markers,
not GetThreadTimes CPU samples. No raw packets or frames are written to stdout.
"""
import argparse
from collections import Counter, OrderedDict
import json
import math
from pathlib import Path
import socket
import struct
import tempfile
import time

MAX_PACKET = 8 << 20
MAX_ELEMENTS = 100000
MAX_AREAS = 4096


class ProtocolError(ValueError):
    pass


class UnsupportedVariant(ProtocolError):
    pass


def encode(value):
    if isinstance(value, bool):
        return struct.pack("<II", 1, int(value))
    if isinstance(value, int):
        return struct.pack("<Ii", 2, value) if -(1 << 31) <= value < 1 << 31 else struct.pack("<Iq", 2 | 65536, value)
    if isinstance(value, float):
        return struct.pack("<Id", 3 | 65536, value)
    if isinstance(value, str):
        data = value.encode("utf-8")
        return struct.pack("<II", 4, len(data)) + data + bytes((-len(data)) % 4)
    if isinstance(value, list):
        return struct.pack("<II", 28, len(value)) + b"".join(encode(item) for item in value)
    if value is None:
        return struct.pack("<I", 0)
    raise TypeError(type(value).__name__)


def packet(value):
    data = encode(value)
    return struct.pack("<I", len(data)) + data


class Decoder:
    def __init__(self, data):
        self.data, self.offset, self.elements = data, 0, 0

    def take(self, size):
        if size < 0 or self.offset + size > len(self.data):
            raise ProtocolError("truncated Variant")
        value = self.data[self.offset:self.offset + size]
        self.offset += size
        return value

    def number(self, fmt):
        return struct.unpack("<" + fmt, self.take(struct.calcsize("<" + fmt)))[0]

    def string(self):
        size = self.number("I")
        data = self.take(size)
        self.take((-size) % 4)
        return data.decode("utf-8")

    def value(self, depth=0):
        self.elements += 1
        if depth > 32 or self.elements > MAX_ELEMENTS:
            raise ProtocolError("Variant complexity limit")
        header = self.number("I")
        kind, wide = header & 255, bool(header & 65536)
        if kind == 0:
            return None
        if kind == 1:
            return bool(self.number("I"))
        if kind == 2:
            return self.number("q" if wide else "i")
        if kind == 3:
            return self.number("d" if wide else "f")
        if kind in (4, 21):
            return self.string()
        if kind == 28:
            # Debugger payloads use untyped arrays. Reject future typed formats
            # explicitly rather than silently shifting the decode cursor.
            if header & ~255:
                raise UnsupportedVariant("typed Array")
            count = self.number("I") & 0x7fffffff
            if count > MAX_ELEMENTS or count * 4 > len(self.data) - self.offset:
                raise ProtocolError("invalid Array size")
            return [self.value(depth + 1) for _ in range(count)]
        if kind in (29, 30, 31, 32, 33, 34):
            count = self.number("I")
            if count > MAX_ELEMENTS:
                raise ProtocolError("packed array limit")
            if kind == 29:
                data = self.take(count)
                self.take((-count) % 4)
                return data
            if kind == 34:
                return [self.string() for _ in range(count)]
            fmt = {30: "i", 31: "q", 32: "f", 33: "d"}[kind]
            return [self.number(fmt) for _ in range(count)]
        raise UnsupportedVariant(f"Variant type {kind}")


def decode(data):
    decoder = Decoder(data)
    value = decoder.value()
    if decoder.offset != len(data):
        raise ProtocolError("trailing Variant bytes")
    return value


class Framer:
    def __init__(self):
        self.buffer = bytearray()

    def feed(self, data):
        self.buffer.extend(data)
        while len(self.buffer) >= 4:
            size = struct.unpack_from("<I", self.buffer)[0]
            if not 4 <= size <= MAX_PACKET:
                raise ProtocolError(f"invalid packet length {size}")
            if len(self.buffer) < size + 4:
                break
            payload = bytes(self.buffer[4:size + 4])
            del self.buffer[:size + 4]
            yield payload


def visual_frame(data):
    if not isinstance(data, list) or len(data) < 2 or type(data[0]) is not int or type(data[1]) is not int:
        raise ProtocolError("malformed visual frame header")
    number, size = data[:2]
    if number < 0 or size < 6 or size % 3 or size > MAX_AREAS * 3 or len(data) != size + 2:
        raise ProtocolError("malformed visual frame size")
    areas = []
    for index in range(2, len(data), 3):
        name, cpu, gpu = data[index:index + 3]
        if not isinstance(name, str) or len(name) > 1024 or not all(
                type(value) in (int, float) and math.isfinite(value) for value in (cpu, gpu)):
            raise ProtocolError("invalid visual timestamp")
        areas.append((name, float(cpu), float(gpu)))
    stages, stack = {}, []
    for index, (name, cpu, gpu) in enumerate(areas[:-1]):
        next_cpu, next_gpu = areas[index + 1][1:]
        if next_cpu < cpu or next_gpu < gpu:
            raise ProtocolError("non-monotonic visual timestamps")
        if name.startswith("<"):
            # The interval starts after closing this scope, so attribute the
            # boundary gap to its parent rather than to the finished group.
            closed = stack.pop() if stack else name[1:]
            path = "/".join(stack + [f"<after {closed.strip()}>"])
        elif name.startswith(">"):
            stack.append(name[1:])
            path = "/".join(stack + ["<begin>"])
        else:
            path = "/".join(stack + [name])
        stage = stages.setdefault(path, {"cpu_ms": 0.0, "gpu_ms": 0.0})
        stage["cpu_ms"] += next_cpu - cpu
        stage["gpu_ms"] += next_gpu - gpu
    return {"frame_number": number, "cpu_ms": areas[-1][1] - areas[0][1],
            "gpu_ms": areas[-1][2] - areas[0][2], "stages": stages}


def distribution(values):
    if not values:
        return {"count": 0}
    ordered = sorted(values)
    return {"count": len(values), "mean": sum(values) / len(values),
            "p50": ordered[(len(values) - 1) // 2],
            "p95": ordered[min(len(values) - 1, math.ceil(len(values) * .95) - 1)],
            "max": ordered[-1]}


class Collector:
    def __init__(self, limit=512, edge_guard=4):
        self.limit, self.edge_guard = limit, edge_guard
        self.phases, self.errors = [], []
        self.counts = Counter()
        self.hardware = None

    def error(self, message):
        self.counts["errors"] += 1
        if len(self.errors) < 12:
            self.errors.append(str(message)[:240])

    def message(self, message):
        if not isinstance(message, list) or len(message) != 3 or not isinstance(message[0], str) or type(message[1]) is not int or not isinstance(message[2], list):
            raise ProtocolError("malformed debugger envelope")
        name, _, data = message
        self.counts["messages"] += 1
        if name == "visual:hardware_info":
            self.hardware = [str(value)[:240] for value in data[:2]]
        elif name == "df3d:render_phase":
            if len(data) != 3 or not isinstance(data[0], str) or len(data[0]) > 80 or data[1] not in ("start", "end") or type(data[2]) is not int:
                raise ProtocolError("invalid phase tag")
            mode, action, number = data
            if action == "start":
                if len(self.phases) >= 16 or any(phase["end_frame"] is None for phase in self.phases):
                    raise ProtocolError("too many or overlapping phases")
                self.phases.append({"mode": mode, "start_frame": number, "end_frame": None,
                                    "samples": OrderedDict(), "dropped_by_limit": 0})
            else:
                matching = [phase for phase in self.phases if phase["mode"] == mode and phase["end_frame"] is None]
                if not matching or number < matching[-1]["start_frame"]:
                    raise ProtocolError("unmatched phase end")
                phase = matching[-1]
                phase["end_frame"] = number
                for frame in list(phase["samples"]):
                    if frame >= number - self.edge_guard:
                        del phase["samples"][frame]
                        self.counts["edge_discarded"] += 1
        elif name == "visual:profile_frame":
            sample = visual_frame(data)
            self.counts["visual_frames"] += 1
            number = sample["frame_number"]
            for phase in reversed(self.phases):
                if number <= phase["start_frame"] + self.edge_guard:
                    continue
                if phase["end_frame"] is not None and number >= phase["end_frame"] - self.edge_guard:
                    continue
                if number in phase["samples"]:
                    self.counts["duplicate_frames"] += 1
                    return
                phase["samples"][number] = sample
                if len(phase["samples"]) > self.limit:
                    phase["samples"].popitem(last=False)
                    phase["dropped_by_limit"] += 1
                return
            self.counts["unassigned_frames"] += 1

    def summary(self, status="complete"):
        phases = []
        for phase in self.phases:
            samples = list(phase["samples"].values())
            stage_names = set(name for sample in samples for name in sample["stages"])
            stages = {}
            for name in sorted(stage_names):
                stages[name] = {axis: distribution([sample["stages"].get(name, {}).get(axis, 0.0)
                                                  for sample in samples]) for axis in ("cpu_ms", "gpu_ms")}
            # Bound the output even if engine instrumentation adds many areas.
            top = sorted(stages, key=lambda name: max(stages[name]["cpu_ms"].get("mean", 0),
                                                     stages[name]["gpu_ms"].get("mean", 0)), reverse=True)[:32]
            outliers = sorted(samples, key=lambda sample: max(sample["cpu_ms"], sample["gpu_ms"]), reverse=True)[:3]
            phases.append({key: phase[key] for key in ("mode", "start_frame", "end_frame", "dropped_by_limit")} | {
                "complete": phase["end_frame"] is not None, "retained_frames": len(samples),
                "first_retained_frame": min(phase["samples"], default=None),
                "last_retained_frame": max(phase["samples"], default=None),
                "cpu_ms": distribution([sample["cpu_ms"] for sample in samples]),
                "gpu_ms": distribution([sample["gpu_ms"] for sample in samples]),
                "stage_count": len(stages), "top_stages": {name: stages[name] for name in top},
                "outliers": [{"frame_number": sample["frame_number"], "cpu_ms": sample["cpu_ms"],
                              "gpu_ms": sample["gpu_ms"], "top_stages": dict(sorted(sample["stages"].items(),
                                  key=lambda item: max(item[1].values()), reverse=True)[:5])} for sample in outliers]})
        return {"schema": 1, "status": status, "profiler": "visual", "hardware": self.hardware,
                "frame_limit_per_phase": self.limit, "edge_guard_frames": self.edge_guard,
                "alignment": "Frame-number ranges with guarded phase edges; buffered GPU timestamps may lag. No wall-clock inference.",
                "timing_semantics": "Elapsed CPU/GPU timestamp differences; stages are adjacent exclusive intervals, not nested totals or thread CPU usage. Statistics describe retained frames only.",
                "counts": dict(self.counts), "errors": self.errors, "phases": phases}


def run(args):
    collector = Collector(args.max_frames, args.edge_guard)
    status, code = "complete", 0
    deadline = time.monotonic() + args.timeout
    try:
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            # The runner polls existence; publish only after complete JSON has
            # been closed, using an atomic rename in the same directory.
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=args.ready.parent,
                                             prefix=args.ready.name + ".", suffix=".tmp", delete=False) as ready:
                json.dump({"port": listener.getsockname()[1]}, ready)
            Path(ready.name).replace(args.ready)
            listener.settimeout(max(.1, deadline - time.monotonic()))
            connection, _ = listener.accept()
            with connection:
                connection.sendall(packet(["profiler:visual", 1, [True]]))
                framer = Framer()
                while True:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise TimeoutError("collector session timeout")
                    connection.settimeout(remaining)
                    data = connection.recv(65536)
                    if not data:
                        if framer.buffer:
                            raise ProtocolError("socket closed mid-packet")
                        break
                    for payload in framer.feed(data):
                        try:
                            collector.message(decode(payload))
                        except UnsupportedVariant:
                            collector.counts["unsupported_packets"] += 1
                            raise
    except (OSError, ValueError, UnicodeError) as error:
        collector.error(error)
        status, code = "error", 1
    if not collector.phases or any(not phase["samples"] or phase["end_frame"] is None for phase in collector.phases):
        collector.error("missing/incomplete phase or no guarded visual samples")
        status, code = "error", 1
    args.output.write_text(json.dumps(collector.summary(status), indent=2), encoding="utf-8")
    return code


def render_summary(result):
    phases = result.get("phases", [])
    lines = [f"Godot visual profile: {result.get('status', 'unknown')}; {len(phases)} phases.",
             "CPU/GPU = elapsed marker intervals, not CPU usage; phases exclude guarded edges."]
    for phase in phases[:3]:
        cpu, gpu = phase.get("cpu_ms", {}), phase.get("gpu_ms", {})
        lines.append(f"{phase['mode'][:80]}: {phase['retained_frames']} frames; "
                     f"CPU mean/p95 {cpu.get('mean', 0):.3f}/{cpu.get('p95', 0):.3f} ms; "
                     f"GPU mean/p95 {gpu.get('mean', 0):.3f}/{gpu.get('p95', 0):.3f} ms")
        stages = sorted(phase.get("top_stages", {}).items(), key=lambda item: max(
            item[1]["cpu_ms"].get("mean", 0), item[1]["gpu_ms"].get("mean", 0)), reverse=True)[:5]
        for name, values in stages:
            lines.append(f"  {name.strip()[:110]}: CPU {values['cpu_ms'].get('mean', 0):.3f}, "
                         f"GPU {values['gpu_ms'].get('mean', 0):.3f} ms mean")
    if len(phases) > 3:
        lines.append(f"{len(phases) - 3} further phases in JSON.")
    for error in result.get("errors", [])[:2]:
        lines.append("Error: " + str(error).replace("\n", " ")[:200])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ready", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--summary", type=Path, help="print a bounded summary of an existing capture; no socket")
    parser.add_argument("--max-frames", type=int, default=512)
    parser.add_argument("--edge-guard", type=int, default=4)
    parser.add_argument("--timeout", type=float, default=600)
    args = parser.parse_args()
    if args.summary:
        if args.ready or args.output:
            parser.error("--summary cannot be combined with --ready or --output")
        print(render_summary(json.loads(args.summary.read_text(encoding="utf-8"))))
        return
    if not args.ready or not args.output:
        parser.error("collector requires --ready and --output")
    if not 1 <= args.max_frames <= 2048 or not 0 <= args.edge_guard <= 30 or args.timeout <= 0:
        parser.error("invalid retention, guard, or timeout limit")
    raise SystemExit(run(args))


if __name__ == "__main__":
    main()
