Build and run the crypto unikernel.

  $ strip() { sed 's/^[^ ]*: //'; }

  $ ./unix/main.exe 2>&1 | strip | grep "sign + verify"
  [INFO] [application] Generated a RSA key of 4096 bits (sign + verify true)
