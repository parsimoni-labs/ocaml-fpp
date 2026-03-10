  $ strip() { sed 's/^[^ ]*: //'; }

  $ ./unix/main.exe 2>&1 | strip
  [INFO] [block] { Mirage_block.read_write = true;
                                              sector_size = 512;
                                              size_sectors = 32768L }
  [ERROR] [block] -- expected failure; got success
  
  [ERROR] [block] -- expected failure; got success
  
  reading 1 sectors at 32768
  [ERROR] [block] -- expected failure; got success
  
  reading 12 sectors at 32757
  [ERROR] [block] -- expected failure; got success
  
  [INFO] [block] Test sequence finished
  [INFO] [block] Total tests started: 10
  [INFO] [block] Total tests passed:  6
  [INFO] [block] Total tests failed:  4
