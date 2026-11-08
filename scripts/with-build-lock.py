#!/usr/bin/env python3
"""Serialize project generation and Xcode use in a shared build directory."""
import fcntl
import os
from pathlib import Path
import sys

if len(sys.argv) < 2:
    raise SystemExit('Usage: with-build-lock.py COMMAND [ARGUMENTS...]')
root = Path(__file__).resolve().parent.parent
(root / 'build').mkdir(exist_ok=True)
lock = (root / 'build' / 'xcode.lock').open('a')
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    print('Waiting for the other build/test using this project directory…', file=sys.stderr, flush=True)
    fcntl.flock(lock, fcntl.LOCK_EX)
# Keep the lock through exec and child processes, including if this command is
# replaced by a shell. The OS releases it when the build process tree exits.
os.set_inheritable(lock.fileno(), True)
os.environ['SCRCPY_BUILD_LOCK_HELD'] = '1'
os.chdir(root)
os.execvpe(sys.argv[1], sys.argv[1:], os.environ)
