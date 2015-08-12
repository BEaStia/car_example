#!/usr/bin/env bash
wget http://download.redis.io/redis-stable.tar.gz
tar xvzf redis-stable.tar.gz
cd redis-stable
make
cd utils
gksudo sh install_server.sh