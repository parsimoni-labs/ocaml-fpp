Build and run the DNS resolver unikernel.

  $ strip() { sed 's/^[^ ]*: //'; }

  $ ./unix/main.exe --domain-name localhost 2>&1 | strip | grep "localhost"
  [INFO] [application] localhost: 127.0.0.1
