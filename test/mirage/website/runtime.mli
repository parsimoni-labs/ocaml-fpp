(** Runtime configuration for website compilation tests. *)

val ipv4_only : bool
val ipv6_only : bool
val aaaa_timeout : 'a option
val connect_delay : 'a option
val connect_timeout : 'a option
val resolve_timeout : 'a option
val resolve_retries : 'a option
val timer_interval : 'a option
val nameservers : 'a option
val timeout : 'a option
val cache_size : 'a option
