#!/bin/sh
# Strip MirageOS log timestamps: "2026-03-09T21:42:33-07:00: [INFO] ..." → "[INFO] ..."
sed 's/^[^ ]*: //'
