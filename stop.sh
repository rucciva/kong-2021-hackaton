#!/bin/bash
set -euo pipefail

docker-compose down 
docker volume rm kong_hydra-sqlite