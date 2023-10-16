#!/usr/bin/env bash

set -e

cd vernemq
make rel
cd _build/default/rel/vernemq

echo "Changing configuration to allow anonymous and SSL..."
mkdir -p etc/conf.d
cat << EOF > etc/conf.d/mqttex.conf
allow_anonymous = on
listener.ssl.name = 127.0.0.1:8883
listener.ssl.certfile = ./etc/cert.pem
listener.ssl.keyfile = ./etc/key.pem
listener.ws.default = 127.0.0.1:8866
EOF

echo "Adding user entry for 'mqttex_basic'..."
echo "mqttex_basic:password" > etc/vmq.passwd
./bin/vmq-passwd -U etc/vmq.passwd

echo "Creating self-signed TLS certificate..."
openssl req -x509 -out etc/cert.pem -keyout etc/key.pem \
  -newkey rsa:2048 -nodes -sha256 \
  -subj '/CN=localhost' -extensions EXT -config <( \
  printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")
