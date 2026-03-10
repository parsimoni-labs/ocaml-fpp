Run the ping6 unikernel on a virtual network (Vnetif).

  $ strip() { sed 's/^[^ ]*: //'; }
  $ timeout 10 ./unix/main.exe 2>&1 | strip | grep "IP6: Started"
  [INFO] [ipv6] IP6: Started with fe80::50:ff:fe00:1
