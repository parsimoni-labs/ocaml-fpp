Run the echo server (simulated input, 10 iterations).

  $ strip() { sed 's/^[^ ]*: //'; }
  $ timeout 30 ./unix/main.exe 2>&1 | strip | grep -c "application"
  10
