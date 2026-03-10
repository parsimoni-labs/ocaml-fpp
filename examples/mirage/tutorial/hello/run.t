Build and run the hello unikernel.

  $ strip() { sed 's/^[^ ]*: //'; }

  $ ./unix/main.exe 2>&1 | strip
  [INFO] [application] hello
  [INFO] [application] hello
  [INFO] [application] hello
  [INFO] [application] hello
