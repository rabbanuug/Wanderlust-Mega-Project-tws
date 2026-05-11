#!/bin/bash

# Local k3s equivalent of updatebackendnew.sh (which uses AWS EC2 to get the IP).
# For local k3s the frontend is always reachable at localhost:31000.
# Change HOST_IP to your machine's LAN IP if accessing the app from another device on the network.
HOST_IP="${WANDERLUST_HOST_IP:-localhost}"

file_to_find="../backend/.env.docker"

if [ ! -f "$file_to_find" ]; then
    echo "ERROR: $file_to_find not found."
    exit 1
fi

sed -i "s|FRONTEND_URL.*|FRONTEND_URL=\"http://${HOST_IP}:31000\"|g" "$file_to_find"
echo "Updated FRONTEND_URL to http://${HOST_IP}:31000"
