#!/usr/bin/env bash
export LD_LIBRARY_PATH="/app/lattice/lib:/app/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}:/run/host/usr/lib64:/run/host/usr/lib64/pulseaudio:/run/host/usr/lib64/samba"
exec /app/lattice/lattice "$@"
