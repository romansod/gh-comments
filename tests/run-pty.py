#!/usr/bin/env python3

"""Run the test suite with a real controlling terminal.

WHY THIS EXISTS
---------------
`run.zsh` on its own can never fail the way a human's terminal does. Whether a
controlling terminal exists is the one input the suite cannot vary from inside
itself, and every context a suite usually runs in answers "no": a CI job, an
agent tool call, a cron run. zsh re-derives COLUMNS/LINES from the controlling
terminal, which redirecting stdin/stdout/stderr does not hide, and a shell
under a terminal hands its children the terminal's signal dispositions. So a
subject with any TTY-dependent path is otherwise verified only in the
environment nobody runs it in. gh-comments reads no terminal geometry today;
this pass is the cheap guarantee that stays true: same suite, same assertions,
one inverted variable.

WHY PYTHON AND NOT `script`
---------------------------
`script(1)`'s BSD and GNU spellings disagree (`script -q /dev/null cmd` vs
`script -q -c "cmd" /dev/null`), and `python3` is on every CI runner.
`pty.fork()` is portable and gives the child a genuine controlling terminal via
setsid + TIOCSCTTY, which is the part that matters.

WHY 300x50 BY DEFAULT
---------------------
A leak shows up only when the real geometry differs from what a case seeded, so
the default must not collide with the values the suites use. A *narrow* pty is
the trap: at 40 columns a case seeding 40 passes by accident. Wide is strictly
better at catching leaks, and rows != columns so a rows/cols swap cannot hide
either.

USAGE
-----
    python3 tests/run-pty.py                    # 300x50, runs run.zsh
    python3 tests/run-pty.py 80x24              # another geometry
    python3 tests/run-pty.py 40x213 -- zsh tests/test-gh-comments.zsh

Exit code is the child's, so this drops into CI in place of `zsh run.zsh`.
Needs no test suite of its own: CI runs it on every push, so a broken runner
fails the build directly.
"""

import fcntl
import os
import pty
import re
import signal
import struct
import sys
import termios

DEFAULT_GEOMETRY = "300x50"
HERE = os.path.dirname(os.path.abspath(__file__))


def parse_args(argv):
    """-> (cols, rows, command). Geometry is COLSxROWS; command follows `--`."""
    geometry, command = DEFAULT_GEOMETRY, None
    args = list(argv)
    if "--" in args:
        split = args.index("--")
        command = args[split + 1:]
        args = args[:split]
    if args:
        geometry = args[0]
    if len(args) > 1:
        sys.exit(f"run-pty: unexpected argument {args[1]!r} (use -- before a command)")
    if not re.fullmatch(r"\d+x\d+", geometry):
        sys.exit(f"run-pty: geometry must be COLSxROWS, got {geometry!r}")
    cols, rows = (int(n) for n in geometry.split("x"))
    if cols < 1 or rows < 1:
        sys.exit(f"run-pty: geometry must be positive, got {geometry!r}")
    if not command:
        command = ["zsh", os.path.join(HERE, "run.zsh")]
    return cols, rows, command


def set_winsize(fd, cols, rows):
    """Size the pty, then read it back — a silent 0x0 would look like a pass."""
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    got_rows, got_cols = struct.unpack(
        "HHHH", fcntl.ioctl(fd, termios.TIOCGWINSZ, struct.pack("HHHH", 0, 0, 0, 0))
    )[:2]
    if (got_cols, got_rows) != (cols, rows):
        sys.exit(
            f"run-pty: pty kept {got_cols}x{got_rows}, wanted {cols}x{rows} — "
            "refusing to run a suite whose geometry is not what was asked for"
        )


def note_in_step_summary(cols, rows):
    """Divide this pass from the off-TTY one in the Actions step summary.

    lib.zsh's t_summary appends, so two passes in one job otherwise produce two
    identically titled reports with nothing marking which is which.
    """
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    try:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(f"\n## 試 pty {cols}x{rows} — controlling terminal present\n")
    except OSError:
        pass  # a summary that cannot be written must not fail the suite


def stream(master):
    """Copy child output to our stdout until EOF, normalising CRLF.

    A pty echoes CRLF line endings; the raw \\r makes local logs and Actions
    logs read oddly. Only this runner's rendered output is touched — every
    assertion inside the suite captures its subject through a pipe, unaffected.
    A chunk can split the CRLF pair, so a trailing \\r is carried over.
    """
    out = sys.stdout.buffer
    carry = b""
    while True:
        try:
            chunk = os.read(master, 65536)
        except OSError:
            break  # EIO on Linux when the last slave fd closes: normal EOF
        if not chunk:
            break
        chunk = carry + chunk
        carry = b""
        if chunk.endswith(b"\r"):
            chunk, carry = chunk[:-1], b"\r"
        out.write(chunk.replace(b"\r\n", b"\n"))
        out.flush()
    if carry:
        out.write(carry)
    out.flush()


def main():
    cols, rows, command = parse_args(sys.argv[1:])
    print(f"  試 pty {cols}x{rows} · {' '.join(command)}", flush=True)
    note_in_step_summary(cols, rows)

    pid, master = pty.fork()
    if pid == 0:
        # Child: a fresh session with the pty as its controlling terminal.
        # Python ignores SIGPIPE at startup and an ignored signal survives
        # exec, so without this the suite would run with a disposition no
        # terminal gives it. Today nothing depends on the difference: every
        # subject is launched inside a `$( )` capture, and zsh resets an
        # inherited-ignored SIGPIPE to default in `$( )` and `( )` subshells,
        # which is why the suite passes either way and why the non-pty pass is
        # safe too. This is so that a subject launched some other way — a
        # direct child, a bare pipeline — dies 141 here like it would in a
        # human's shell, rather than getting `write error` and exit 1 in the
        # pty pass alone. Cheap, and it keeps the two passes on one axis.
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
        try:
            os.execvp(command[0], command)
        except OSError as exc:
            print(f"run-pty: cannot exec {command[0]!r}: {exc}", file=sys.stderr)
            os._exit(127)

    # Size it before the suite can ask, and the readback in set_winsize turns
    # any failure into a loud one.
    set_winsize(master, cols, rows)
    stream(master)
    _, status = os.waitpid(pid, 0)
    code = os.waitstatus_to_exitcode(status)
    # Signal death comes back as -signum; report it the way a shell does
    # (128+signum) instead of letting sys.exit wrap it into 256-signum.
    sys.exit(128 - code if code < 0 else code)


if __name__ == "__main__":
    main()
