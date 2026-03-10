Build and run the disk-lottery unikernel.

  $ strip() { sed 's/^[^ ]*: //'; }

Reset the game state (deterministic output):

  $ ./unix/main.exe --reset 2>&1 | strip
   [application] Reset game slot 0.
