Run the DHCP server unikernel on a virtual network (Vnetif).

  $ strip() { sed 's/^[^ ]*: //'; }
  $ timeout 3 ./unix/main.exe 2>&1 | strip | grep "gratuitous ARP"
  [INFO] [ARP] Sending gratuitous ARP for 192.168.1.5 (02:50:00:00:00:01)
