Build and run the hello-key unikernel.

  $ strip() { sed 's/^[^ ]*: //'; }

  $ ./unix/main.exe 2>&1 | strip
  [INFO] [application] Hello World!
  [INFO] [application] Hello World!
  [INFO] [application] Hello World!
  [INFO] [application] Hello World!
