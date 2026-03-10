Build and run the docteur unikernel.

  $ strip() { sed 's/^[^ ]*: //'; }

  $ ./unix/main.exe --filename hello 2>&1 | strip | head -1
  [INFO] [application] Hello from docteur!
