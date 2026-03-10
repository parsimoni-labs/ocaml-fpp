Build and run the clock unikernel (runs forever, so use a timeout).

  $ strip() { sed 's/^[^ ]*: //'; }

  $ timeout 3 ./unix/main.exe 2>&1 | strip | grep -q "BEEP"
