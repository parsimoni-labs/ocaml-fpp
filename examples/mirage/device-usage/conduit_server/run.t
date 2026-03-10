Build and run the conduit HTTP server.

  $ strip() { sed 's/^[^ ]*: //'; }

Start the server on port 80, fetch a page, then kill the server:

  $ timeout 10 sh -c '
  > ./unix/main.exe &
  > sleep 2
  > curl -s http://127.0.0.1:80/
  > kill $! 2>/dev/null
  > wait' 2>&1 | strip | grep -v "^\[" | head -1
  hello mirage world!
