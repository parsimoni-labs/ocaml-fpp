Build and run the static_website_tls unikernel (HTTP redirects to HTTPS).

  $ strip() { sed 's/^[^ ]*: //'; }

  $ timeout 5 sh -c '
  > ./unix/main.exe --http 18083 --https 18443 2>/dev/null &
  > sleep 2
  > curl -sI http://127.0.0.1:18083/ | head -1
  > kill $! 2>/dev/null
  > wait' 2>&1 | grep "301"
  HTTP/1.1 301 Moved Permanently
