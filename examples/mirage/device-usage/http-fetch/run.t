Build and run the http-fetch unikernel with a local HTTP server.

  $ strip() { sed 's/^[^ ]*: //'; }

  $ timeout 10 sh -c '
  > printf "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello" | nc -l 18081 > /dev/null &
  > sleep 1
  > ./unix/main.exe --uri http://127.0.0.1:18081/ 2>&1
  > ' | strip | grep "body length"
   [application] Received body length: 5
