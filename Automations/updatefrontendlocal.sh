#!/bin/bash

# Local k3s equivalent of updatefrontendnew.sh (which uses AWS EC2 to get the IP).
# For local k3s the backend API is always reachable at localhost:31100.
# Change HOST_IP to your machine's LAN IP if accessing the app from another device on the network.
HOST_IP="localhost"

file_to_find="../frontend/.env.docker"

if [ ! -f "$file_to_find" ]; then
    echo "ERROR: $file_to_find not found."
    exit 1
fi

sed -i "s|VITE_API_PATH.*|VITE_API_PATH=\"http://${HOST_IP}:31100\"|g" "$file_to_find"
echo "Updated VITE_API_PATH to http://${HOST_IP}:31100"
