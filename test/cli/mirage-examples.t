MirageOS examples: generate main.ml from FPP topologies.

  $ F="../../examples/mirage"

Standalone app generates start entry point (no module alias needed)
  $ ofpp to-ml --topologies UnixHello $F/mirage.fpp $F/tutorial/hello/config.fpp 2>/dev/null
  $ grep -E 'Unikernel.start' main.ml
  let start = lazy (Unikernel.start ())

All standalone topologies generate start call
  $ for t in hello hello-key; do
  >   ofpp to-ml --topologies "$(grep -o 'Unix[A-Za-z]*' $F/tutorial/$t/config.fpp)" $F/mirage.fpp $F/tutorial/$t/config.fpp 2>/dev/null
  >   grep -q 'Unikernel.start' main.ml && echo "$t: OK" || echo "$t: FAIL"
  > done
  hello: OK
  hello-key: OK

Block topology generates connect call with port params
  $ ofpp to-ml --topologies UnixBlock $F/mirage.fpp $F/device-usage/block/config.fpp 2>/dev/null
  $ grep 'Ramdisk.connect' main.ml
    let* ramdisk = Ramdisk.connect ~name:"block-test" in

KV topology wires static store via functor
  $ ofpp to-ml --topologies UnixKvRo $F/mirage.fpp $F/device-usage/kv_ro/config.fpp 2>/dev/null
  $ grep -E '(Static_t|Unikernel)' main.ml
  module type Static_t = Mirage_kv.RO
  module Unikernel = Unikernel.Main(Static_t)
    let* static_t = Static_t.connect () in
    Unikernel.start static_t)

Socket stack topologies use port params for connect args
  $ ofpp to-ml --topologies UnixNetwork $F/mirage.fpp $F/device-usage/network/config.fpp 2>/dev/null
  $ grep -E '(Stackv4v6|Udpv4v6|Tcpv4v6|Unikernel)' main.ml | head -8
  module type Udpv4v6_socket = Tcpip.Udp.S
  module type Tcpv4v6_socket = Tcpip.Tcp.S
  module type Stackv4v6 = Tcpip.Stack.V4V6
  module Stackv4v6 = Stackv4v6.Make(Udpv4v6_socket)(Tcpv4v6_socket)
  module Unikernel = Unikernel.Main(Stackv4v6)
    let* udpv4v6_socket = Udpv4v6_socket.connect ~ipv4_only:false ~ipv6_only:false (Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0") None in
    let* tcpv4v6_socket = Tcpv4v6_socket.connect ~ipv4_only:false ~ipv6_only:false (Ipaddr.V4.Prefix.of_string_exn "0.0.0.0/0") None in
    Stackv4v6.connect udpv4v6_socket tcpv4v6_socket)

Dhcp topology uses Netif with positional device port param
  $ ofpp to-ml --topologies UnixDhcp $F/mirage.fpp $F/applications/dhcp/config.fpp 2>/dev/null
  $ grep -E '(Netif|Unikernel)' main.ml
  module type Netif = Mirage_net.S
  module Unikernel = Unikernel.Main(Netif)
    let* netif = Netif.connect "tap0" in
    Unikernel.start netif)

Ping6 topology wires Ethernet and IPv6 functors
  $ ofpp to-ml --topologies UnixPing6 $F/mirage.fpp $F/device-usage/ping6/config.fpp 2>/dev/null
  $ grep -E 'module (Eth|Ipv6|Unikernel)' main.ml
  module Ethernet = Ethernet.Make(Netif)
  module Ipv6 = Ipv6.Make(Netif)(Ethernet)
  module Unikernel = Unikernel.Main(Netif)(Ethernet)(Ipv6)

Conduit topology uses adapter with start method
  $ ofpp to-ml --topologies UnixConduit $F/mirage.fpp $F/device-usage/conduit_server/config.fpp 2>/dev/null
  $ grep -E '(Conduit_tcp|Unikernel)' main.ml
  module type Conduit_tcp = Conduit_mirage.S
  module Conduit_tcp = Conduit_tcp.Make(Stackv4v6)
  module Unikernel = Unikernel.Main(Conduit_tcp)
    let* conduit_tcp = Conduit_tcp.start stackv4v6 in
    Unikernel.start conduit_tcp)

DNS topology uses adapter with start method
  $ ofpp to-ml --topologies UnixDns $F/mirage.fpp $F/applications/dns/config.fpp 2>/dev/null
  $ grep -E '(Dns_client|Happy_eyeballs|Unikernel)' main.ml
  module type Happy_eyeballs_mirage = Happy_eyeballs_mirage.S
  module type Dns_client = Dns_client_mirage.S
  module Happy_eyeballs_mirage = Happy_eyeballs_mirage.Make(Stackv4v6)
  module Dns_client = Dns_resolver.Make(Stackv4v6)(Happy_eyeballs_mirage)
  module Unikernel = Unikernel.Make(Dns_client)
    let* happy_eyeballs_mirage = Happy_eyeballs_mirage.connect_device stackv4v6 in
    let* dns_client = Dns_client.start stackv4v6 happy_eyeballs_mirage in
    Unikernel.start dns_client)

Tar-backed KV store reads from block device
  $ ofpp to-ml --topologies UnixTarKv $F/mirage.fpp $F/device-usage/tar-kv/config.fpp 2>/dev/null
  $ grep -E '(Data_block|Tar_data|Unikernel)' main.ml
  module type Data_block = Mirage_block.S
  module type Tar_data = Mirage_kv.RO
  module Tar_data = Tar_mirage.Make_KV_RO(Data_block)
  module Unikernel = Unikernel.Main(Tar_data)
    let* data_block = Data_block.connect ~name:"data.tar" in
    let* tar_data = Tar_data.connect data_block in
    Unikernel.start tar_data)

FAT-backed KV store with data and certs on separate block devices
  $ ofpp to-ml --topologies UnixFatKv $F/mirage.fpp $F/device-usage/fat-kv/config.fpp 2>/dev/null
  $ grep -E '(Data_block|Certs_block|Fat_data|Fat_certs|Unikernel)' main.ml
  module type Data_block = Mirage_block.S
  module type Certs_block = Mirage_block.S
  module type Fat_data = Mirage_kv.RO
  module type Fat_certs = Mirage_kv.RO
  module Fat_data = Fat.KV_RO(Data_block)
  module Fat_certs = Fat.KV_RO(Certs_block)
  module Unikernel = Unikernel.Main(Fat_data)(Fat_certs)
    let* data_block = Data_block.connect ~name:"data.img" in
    let* certs_block = Certs_block.connect ~name:"certs.img" in
    let* fat_data = Fat_data.connect data_block in
    let* fat_certs = Fat_certs.connect certs_block in
    Unikernel.start fat_data fat_certs)

Static website uses crunch'd KV stores and socket stack
  $ ofpp to-ml --topologies UnixStaticWebsite $F/mirage.fpp $F/applications/static-website/config.fpp 2>/dev/null
  $ grep -E '(Htdocs_data|Data|Certs|Unikernel)' main.ml
  module type Htdocs_data = Mirage_kv.RO
  module type Data = Mirage_kv.RO
  module type Certs = Mirage_kv.RO
  module Unikernel = Unikernel.Main(Htdocs_data)(Data)(Certs)(Stackv4v6)
    let* htdocs_data = Htdocs_data.connect () in
    let* data = Data.connect () in
    let* certs = Certs.connect () in
    Unikernel.start htdocs_data data certs stackv4v6)

TLS server uses tar-backed certs and crunch'd TLS data
  $ ofpp to-ml --topologies UnixTlsServer $F/mirage.fpp $F/applications/tls-server/config.fpp 2>/dev/null
  $ grep -E '(Certs_block|Tar_certs|Tls_data|Unikernel)' main.ml
  module type Certs_block = Mirage_block.S
  module type Tar_certs = Mirage_kv.RO
  module type Tls_data = Mirage_kv.RO
  module Tar_certs = Tar_mirage.Make_KV_RO(Certs_block)
  module Unikernel = Unikernel.Main(Tar_certs)(Tls_data)(Stackv4v6)
    let* certs_block = Certs_block.connect ~name:"certs.tar" in
    let* tar_certs = Tar_certs.connect certs_block in
    let* tls_data = Tls_data.connect () in
    Unikernel.start tar_certs tls_data stackv4v6)

Noop topology generates no start call
  $ ofpp to-ml --topologies UnixNoop $F/mirage.fpp $F/tutorial/noop/config.fpp 2>/dev/null
  $ grep -c 'Lazy.force' main.ml
  0

All new standalone topologies generate start call
  $ for t in app_info local-library; do
  >   ofpp to-ml --topologies "$(grep -o 'Unix[A-Za-z]*' $F/tutorial/$t/config.fpp)" $F/mirage.fpp $F/tutorial/$t/config.fpp 2>/dev/null
  >   grep -q 'Unikernel.start' main.ml && echo "$t: OK" || echo "$t: FAIL"
  > done
  app_info: OK
  local-library: OK

Lwt tutorial sub-examples all generate start call
  $ for t in heads1 heads2 echo_server timeout1 timeout2; do
  >   ofpp to-ml --topologies "$(grep -o 'Unix[A-Za-z0-9]*' $F/tutorial/lwt/$t/config.fpp)" $F/mirage.fpp $F/tutorial/lwt/$t/config.fpp 2>/dev/null
  >   grep -q 'Unikernel.start' main.ml && echo "$t: OK" || echo "$t: FAIL"
  > done
  heads1: OK
  heads2: OK
  echo_server: OK
  timeout1: OK
  timeout2: OK

Littlefs topology wires block device through chamelon RW store
  $ ofpp to-ml --topologies UnixLittlefs $F/mirage.fpp $F/device-usage/littlefs/config.fpp 2>/dev/null
  $ grep -E '(Block|Chamelon|Unikernel)' main.ml
  module type Block = Mirage_block.S
  module type Chamelon = Mirage_kv.RW
  module Chamelon = Chamelon.Make(Block)
  module Unikernel = Unikernel.Make(Chamelon)
    let* block = Block.connect ~name:"littlefs" in
    let* chamelon = Chamelon.connect ~program_block_size:16 block in
    Unikernel.start chamelon)

Docteur topology uses KV store (same pattern as kv_ro)
  $ ofpp to-ml --topologies UnixDocteur $F/mirage.fpp $F/applications/docteur/config.fpp 2>/dev/null
  $ grep -E '(Static_t|Unikernel)' main.ml
  module type Static_t = Mirage_kv.RO
  module Unikernel = Unikernel.Make(Static_t)
    let* static_t = Static_t.connect () in
    Unikernel.start static_t)

Pgx topology wires socket stack to unikernel
  $ ofpp to-ml --topologies UnixPgx $F/mirage.fpp $F/device-usage/pgx/config.fpp 2>/dev/null
  $ grep -E '(Stackv4v6|Unikernel)' main.ml | head -4
  module type Stackv4v6 = Tcpip.Stack.V4V6
  module Stackv4v6 = Stackv4v6.Make(Udpv4v6_socket)(Tcpv4v6_socket)
  module Unikernel = Unikernel.Make(Stackv4v6)
    Unikernel.start stackv4v6)

Static website with TLS uses KV stores and socket stack
  $ ofpp to-ml --topologies UnixStaticWebsiteTls $F/mirage.fpp $F/applications/static_website_tls/config.fpp 2>/dev/null
  $ grep -E '(Static_data|Tls_keys|Dispatch|Unikernel)' main.ml
  module type Static_data = Mirage_kv.RO
  module type Tls_keys = Mirage_kv.RO
  module Dispatch = Dispatch.HTTPS(Static_data)(Tls_keys)(Stackv4v6)
    let* static_data = Static_data.connect () in
    let* tls_keys = Tls_keys.connect () in
    Dispatch.start static_data tls_keys stackv4v6)

Entry points include Mirage_runtime boilerplate
  $ ofpp to-ml --topologies UnixHello $F/mirage.fpp $F/tutorial/hello/config.fpp 2>/dev/null
  $ grep -c 'Mirage_runtime' main.ml
  6
