  $ strip() { sed 's/^[^ ]*: //'; }

  $ ./unix/main.exe 2>&1 | strip
  [INFO] [application] Contents of extremely secret vital storage confirmed!
