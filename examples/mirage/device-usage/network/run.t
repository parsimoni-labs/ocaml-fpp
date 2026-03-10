Build and run the network TCP echo server.

  $ strip() { sed 's/^[^ ]*: //'; }

Start the server, connect to it, then kill the server:

  $ timeout 5 sh -c '
  > ./unix/main.exe --port 18080 &
  > sleep 1
  > echo hello | nc -w 1 127.0.0.1 18080
  > kill $! 2>/dev/null
  > wait' 2>&1 | strip | grep "new tcp connection" | sed 's/port [0-9]*/port PORT/'
  [INFO] [application] new tcp connection from IP 127.0.0.1 on port PORT
