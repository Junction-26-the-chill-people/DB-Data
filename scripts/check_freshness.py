"""Fetch origin/main and compare ancestry without changing the working tree."""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*args, check=True):
    return subprocess.run(['git', *args], cwd=ROOT, text=True, capture_output=True, check=check)


def main():
    try:
        run('fetch', 'origin', '+refs/heads/main:refs/remotes/origin/main')
        local = run('rev-parse', 'HEAD').stdout.strip()
        remote = run('rev-parse', 'refs/remotes/origin/main').stdout.strip()
        dirty = bool(run('status', '--porcelain').stdout.strip())
        print(f'Local: {local}\nRemote main: {remote}')
        if dirty:
            print('NOTICE: working tree has local changes; preserve them before reconciling.')
        if local == remote:
            print('CURRENT: local HEAD equals fetched origin/main.')
            return 0
        ahead = run('merge-base', '--is-ancestor', remote, local, check=False)
        if ahead.returncode == 0:
            print('AHEAD: HEAD includes origin/main; local commits may be unshared/unreleased.')
            return 0
        behind = run('merge-base', '--is-ancestor', local, remote, check=False)
        if ahead.returncode > 1 or behind.returncode > 1:
            print('UNKNOWN: ancestry could not be verified; inspect Git history/shallow clone.')
            return 2
        print('STALE: origin/main has newer commits.' if behind.returncode == 0 else
              'DIVERGED: reconcile local and origin/main history before DB changes.')
        return 1
    except (OSError, subprocess.CalledProcessError) as e:
        # Do not echo remote URLs or credential-helper output; those can contain secrets.
        print(f'UNKNOWN: Git fetch/comparison failed ({type(e).__name__}); freshness is unverified.', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
