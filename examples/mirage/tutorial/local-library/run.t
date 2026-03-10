Build and run the local-library unikernel.

  $ strip() { sed 's/^[^ ]*: //'; }

  $ ./unix/main.exe 2>&1 | strip
  [INFO] [application] The hello library has a message for you: Hello!
