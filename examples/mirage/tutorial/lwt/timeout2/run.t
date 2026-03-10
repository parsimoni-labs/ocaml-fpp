Run the timeout2 unikernel (race between 0-3s random delay and 2s timeout).

  $ strip() { sed 's/^[^ ]*: //'; }
  $ timeout 10 ./unix/main.exe 2>&1 | strip | grep -cE "(Cancelled|Returned)"
  1
