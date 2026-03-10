Build and run the littlefs unikernel.

  $ strip() { sed 's/^[^ ]*: //'; }

Create and format a 512K block device file for littlefs:

  $ dd if=/dev/zero of=littlefs bs=512 count=1024 2>/dev/null
  $ chamelon format littlefs 512 2>/dev/null
  Formatting littlefs as a littlefs filesystem with block size 512

Run the unikernel (writes and reads back "Hello World!"):

  $ ./unix/main.exe 2>&1 | strip | head -1
  [INFO] [application] foo: 00000000: 4865 6c6c 6f20 576f 726c 6421            Hello World!
