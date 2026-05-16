#!/bin/bash

pids=$(pidof hyprsunset)

if [[ -n "$pids" ]]; then
    kill $pids
else
    hyprsunset &
fi
