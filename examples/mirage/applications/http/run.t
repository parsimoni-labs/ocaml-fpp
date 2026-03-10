Build and run the HTTP (Paf) server unikernel.

  $ strip() { sed 's/^[^ ]*: //'; }

  $ timeout 15 sh -c '
  > ./unix/main.exe &
  > sleep 3
  > curl -s http://127.0.0.1:8080/ | head -1
  > kill $! 2>/dev/null
  > wait' 2>&1 | strip | grep -v "^\[" | head -1
  Hello fellows!
