Build and run the git unikernel against a local git daemon.

  $ git init --bare repo.git 2>&1 | grep -c Initialized
  1
  $ timeout 15 sh -c '
  > git daemon --reuseaddr --listen=127.0.0.1 --base-path=. --export-all --enable=receive-pack --port=19418 . 2>/dev/null &
  > sleep 1
  > ./unix/main.exe --remote git://127.0.0.1:19418/repo.git --branch refs/heads/main 2>/dev/null
  > RET=$?
  > kill %1 2>/dev/null
  > wait 2>/dev/null
  > exit $RET'
  $ git --git-dir=repo.git rev-parse --verify refs/heads/main >/dev/null 2>&1 && echo "push ok"
  push ok
