"""Run a command on a pseudo-terminal and answer its prompts.

Usage: pty_drive.py PROMPT=ANSWER [PROMPT=ANSWER ...] -- COMMAND [ARGS...]

Each answer is sent once, in order, after its prompt text appears. Prints
everything the command wrote and exits with the command's status.
"""

import os
import pty
import select
import sys
import time


def main():
    sep = sys.argv.index("--")
    pairs = [arg.split("=", 1) for arg in sys.argv[1:sep]]
    cmd = sys.argv[sep + 1:]
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(cmd[0], cmd)
    out = b""
    seen = 0
    deadline = time.time() + 120
    while time.time() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            out += chunk
        if pairs and pairs[0][0].encode() in out[seen:]:
            seen = out.index(pairs[0][0].encode(), seen) + len(pairs[0][0])
            os.write(fd, pairs[0][1].encode() + b"\n")
            pairs.pop(0)
    else:
        os.kill(pid, 9)
    _, status = os.waitpid(pid, 0)
    sys.stdout.write(out.decode(errors="replace"))
    sys.exit(os.waitstatus_to_exitcode(status))


main()
