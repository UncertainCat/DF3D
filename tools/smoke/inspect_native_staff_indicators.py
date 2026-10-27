"""Read-only, build-pinned staff-indicator artwork dispatch evidence.

No process attachment or native UI state is used. Output contains selectors and
asset token names, never installed artwork. Runtime does not consume this file.
"""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path
import capstone
import pefile

EXPECTED = "205770918fd54c96cbbcf89223ebd449e2e113c7c873ed81177c4511a3450db7"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", default="C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress/Dwarf Fortress.exe")
    parser.add_argument("--output", default="build/native-staff-indicators.json")
    args = parser.parse_args()
    raw = Path(args.exe).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == EXPECTED, "unsupported DF executable"
    pe = pefile.PE(data=raw)
    dis = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    dis.detail = True
    def first(address):
        return next(dis.disasm(pe.get_data(address, 15), address))
    def rip(instruction):
        return next(instruction.address + instruction.size + o.mem.disp
                    for o in instruction.operands
                    if o.type == capstone.CS_OP_MEM and o.mem.base == capstone.x86.X86_REG_RIP)
    # Resolve the building-icon global back to its installed token binding.
    # Each parser arm compares its literal token before storing the texture ID.
    section = next(s for s in pe.sections if s.Name.startswith(b".text"))
    data = section.get_data()
    bindings = {}
    for match in re.finditer(rb"\x89[\x05\x0d\x15\x1d\x25\x2d\x35\x3d](....)", data, re.S):
        address = section.VirtualAddress + match.start()
        target = address + 6 + struct.unpack("<i", match[1])[0]
        if not 0x264b000 <= target <= 0x264b200:
            continue
        prefix = pe.get_data(address - 100, 100)
        names = []
        for lea in re.finditer(rb"\x48\x8d\x15(....)", prefix, re.S):
            at = address - 100 + lea.start()
            string_at = at + 7 + struct.unpack("<i", lea[1])[0]
            name = pe.get_data(string_at, 100).split(b"\0")[0]
            if name.startswith(b"BUILDING_ICON_"):
                names.append(name.decode("ascii"))
        if names:
            assert len(names) == 1
            bindings[target] = {"token": names[0], "binding_rva": hex(address)}
    evidence = {"exe_sha256": EXPECTED, "tables": {}}
    for name, table, count in [("occupation", 0x3b9144, 11), ("workshop", 0x3b919c, 25),
                               ("furnace", 0x3b9200, 8), ("work_detail", 0x3b9220, 19)]:
        rows = []
        for value in range(count):
            target = struct.unpack("<I", pe.get_data(table + value * 4, 4))[0]
            instruction = first(target)
            row = {"value": value, "branch_rva": hex(target)}
            if instruction.mnemonic == "mov" and instruction.operands[1].type == capstone.CS_OP_IMM:
                row["graphic_enum"] = instruction.operands[1].imm
            elif instruction.mnemonic == "mov":
                address = rip(instruction)
                assert address in bindings, hex(address)
                row.update(bindings[address]); row["graphic_global_rva"] = hex(address)
            elif name == "occupation":
                assert value == 6 and target == 0x3b887f
                row["skip_without_slot"] = True
            else:
                assert (name, value) in [("workshop", 23), ("furnace", 7)]
                fallback = 0x264b00c if name == "workshop" else 0x264b03c
                row["custom_raw_list_icon"] = True
                row["fallback"] = bindings[fallback]
            rows.append(row)
        evidence["tables"][name] = rows
    evidence["limitations"] = ["Static dispatch evidence complements protected native captures; it does not prove rendered parity.",
        "Hover hitbox and occupation-art defects remain subject to maintainer approval."]
    destination = Path(args.output)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(evidence, indent=2) + "\n")
    print(destination)

if __name__ == "__main__":
    main()
