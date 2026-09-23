"""Verify bounded CMake embedding without compiling or launching Dwarf Fortress."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
cmake = shutil.which('cmake')
assert cmake, 'CMake is required for the embedding test'
actual = (root / 'bridge/plugin/trade.lua').read_bytes()
actual = actual.replace(b'\r\n', b'\n')  # C++ raw-literal runtime line endings
synthetic = ('local x="semicolon; @token@ $value café"\n' * 1200).encode('utf-8')
with tempfile.TemporaryDirectory(prefix='df3d-lua-embedding-') as tmp:
    directory = Path(tmp)
    for source in [actual, synthetic]:
        (directory / 'source.lua').write_bytes(source)
        (directory / 'expression.in').write_text('@expression@', encoding='utf-8')
        script = f'''include("{(root / 'bridge/plugin/embed_lua.cmake').as_posix()}")
file(READ "{directory.as_posix()}/source.lua" source)
df3d_lua_expression(expression "${{source}}")
configure_file("{directory.as_posix()}/expression.in" "{directory.as_posix()}/expression.txt" @ONLY NEWLINE_STYLE UNIX)
'''
        (directory / 'test.cmake').write_text(script, encoding='utf-8')
        subprocess.run([cmake, '-P', str(directory / 'test.cmake')], check=True)
        expression = (directory / 'expression.txt').read_bytes()
        chunks = re.findall(rb'R"DF3D\((.*?)\)DF3D"', expression, re.DOTALL)
        assert len(chunks) >= 1
        assert all(0 < len(chunk) <= 8192 for chunk in chunks), [len(chunk) for chunk in chunks]
        assert b''.join(chunks) == source
        for chunk in chunks:
            chunk.decode('utf-8')
print('LUA_EMBEDDING_PASS')
