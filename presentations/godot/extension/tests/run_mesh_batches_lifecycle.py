"""Run the optional real-engine MeshBatches lifecycle regression harness.

Build target df3d_mesh_batches_test first. This assembles an isolated, ignored
Godot project, so test registration never enters the production extension.
"""
import argparse
from pathlib import Path
import os
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', required=True, type=Path)
parser.add_argument('--dll', type=Path)
parser.add_argument('--build-dir', type=Path, help='Build the optional harness target before running')
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
if not args.dll and not args.build_dir:
 parser.error('--dll or --build-dir is required')
env = dict(os.environ)
env['PATH'] = env.get('DF3D_MINGW_BIN', 'C:/msys64/mingw64/bin') + os.pathsep + env['PATH']
if args.build_dir:
 subprocess.run(['cmake', '--build', str(args.build_dir), '--target', 'df3d_mesh_batches_test', '--parallel', '4'], env=env, check=True, timeout=300)
 if not args.dll:
  args.dll = args.build_dir / 'mesh-batches-test/df3d_mesh_batches_test.dll'
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
(out / 'project.godot').write_text('config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding='utf-8')
(out / 'test.gdextension').write_text('[configuration]\nentry_symbol="mesh_batches_test_init"\ncompatibility_minimum="4.7"\n[libraries]\nwindows.x86_64="' + args.dll.resolve().as_posix() + '"\n', encoding='utf-8')
(out / 'run.gd').write_text('''extends SceneTree
func _initialize(): call_deferred("run")
func run():
 var error=GDExtensionManager.load_extension("res://test.gdextension")
 if error!=GDExtensionManager.LOAD_STATUS_OK and error!=GDExtensionManager.LOAD_STATUS_ALREADY_LOADED:
  push_error("test extension failed to load: %s" % error)
  quit(1)
  return
 var test=ClassDB.instantiate("MeshBatchesTest")
 var failures=test.run(root)
 for failure in failures: push_error(failure)
 print("MESH_BATCHES_LIFECYCLE failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
''', encoding='utf-8')
command = [str(args.godot.resolve()), '--headless', '--path', str(out), '--script', 'res://run.gd']
with (out / 'engine.log').open('w', encoding='utf-8') as log:
 result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=120)
print((out / 'engine.log').read_text(encoding='utf-8'))
raise SystemExit(result.returncode)
