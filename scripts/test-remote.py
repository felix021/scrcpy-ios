#!/usr/bin/env python3
"""Run owned iOS simulator UI tests while keeping their ADB test tunnel alive."""
import argparse
from pathlib import Path
import shlex
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--mac', required=True, help='SSH host alias from private local configuration')
p.add_argument('--simulator', required=True, help='Owned simulator UUID')
p.add_argument('--adb-port', type=int, required=True, help='Local adb-forward port for the owned Android target')
p.add_argument('--remote-port', type=int, default=15555)
p.add_argument('--rig', default='code/scrcpy-ios-build', help='Dedicated build directory relative to the Mac home')
p.add_argument('--output', type=Path, required=True, help='Artifacts directory outside the repository')
p.add_argument('--audio', action='store_true', help='Enable native remote audio playback in the test app')
p.add_argument('--codec', choices=['h264', 'h265'], default='h264')
p.add_argument('--only', default='ScrcpyUITests/ScrcpyUITests/testRealAndroidConnection')
a = p.parse_args()
if a.output.resolve().is_relative_to(Path(__file__).resolve().parent.parent):
    p.error("--output must be outside the source repository")
a.output.mkdir(parents=True, exist_ok=True)
assert 1 <= a.adb_port <= 65535 and 1 <= a.remote_port <= 65535
result = 'UITests-' + str(time.time_ns()) + '.xcresult'
ssh = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15']
with (a.output / 'tunnel.log').open('w') as log:
    tunnel = subprocess.Popen(ssh + ['-o', 'ControlMaster=no', '-o', 'ControlPath=none', '-o', 'ControlPersist=no', '-o', 'ExitOnForwardFailure=yes', '-o', 'ServerAliveInterval=20', '-N', '-R', f'127.0.0.1:{a.remote_port}:127.0.0.1:{a.adb_port}', a.mac], stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
    try:
        time.sleep(1)
        if tunnel.poll() is not None:
            raise SystemExit('ADB test tunnel failed; see tunnel.log')
        rig = '$HOME/' + shlex.quote(a.rig)
        command = f'cd {rig} && /usr/bin/nc -z -w 5 127.0.0.1 {a.remote_port} && TEST_RUNNER_SCRCPY_TEST_HOST=127.0.0.1 TEST_RUNNER_SCRCPY_TEST_PORT={a.remote_port} TEST_RUNNER_SCRCPY_TEST_AUDIO={int(a.audio)} TEST_RUNNER_SCRCPY_TEST_CODEC={a.codec} /usr/bin/xcodebuild -project Scrcpy.xcodeproj -scheme Scrcpy -configuration Debug -destination {shlex.quote("platform=iOS Simulator,id="+a.simulator)} -derivedDataPath build/simulator -resultBundlePath build/{result} -parallel-testing-enabled NO -only-testing:{shlex.quote(a.only)} CODE_SIGN_IDENTITY=- test'
        with (a.output / 'xcodebuild.log').open('w') as output:
            code = subprocess.run(ssh + [a.mac, command], stdout=output, stderr=subprocess.STDOUT).returncode
        print('Remote result bundle:', a.rig + '/build/' + result, flush=True)
        (a.output / 'result-bundle.txt').write_text(a.rig + '/build/' + result + '\n')
        raise SystemExit(code)
    finally:
        tunnel.terminate()
        try:
            tunnel.wait(timeout=5)
        except subprocess.TimeoutExpired:
            tunnel.kill()
            tunnel.wait()
