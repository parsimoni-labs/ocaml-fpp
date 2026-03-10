  $ strip() { sed 's/^[^ ]*: //'; }

  $ ./unix/main.exe 2>&1 | strip
  [INFO] [application] Heads
  [INFO] [application] Tails
  [INFO] [application] Finished
