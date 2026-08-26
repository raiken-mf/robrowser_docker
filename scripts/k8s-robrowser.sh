#!/usr/bin/env bash
set -e

# Prüfen ob .env existiert
if [ ! -f .env ]; then
  echo "Fehler: .env Datei nicht gefunden!"
  exit 1
fi

# .env laden und exportieren
set -a
source .env
set +a

# Defaults setzen falls nicht in .env definiert
export PORT_HTTP=${PORT_HTTP:-"30080"}
export PORT_WSPROXY=${PORT_WSPROXY:-"30599"}
export HOST=${HOST:-"127.0.0.1"}
export PACKETVER=${PACKETVER:-"20211103"}
export PACKET_OBFUSCATION_KEY1=${PACKET_OBFUSCATION_KEY1:-"0x6DED6DEE"}
export PACKET_OBFUSCATION_KEY2=${PACKET_OBFUSCATION_KEY2:-"0x3DFD6AED"}
export PACKET_OBFUSCATION_KEY3=${PACKET_OBFUSCATION_KEY3:-"0x0A3D5C0D"}

echo "==> Deploye roBrowser mit Host: ${HOST}, HTTP-Port: ${PORT_HTTP}..."

# Namespace sicherstellen
kubectl get namespace ragnarok >/dev/null 2>&1 || kubectl apply -f k8s/namespace.yaml

kubectl apply -f k8s/wsproxy.yaml
kubectl apply -f k8s/pvc-client-data.yaml

# Template via envsubst befüllen und direkt an kubectl übergeben
envsubst < k8s/robrowser.template.yaml | kubectl apply -f -

kubectl rollout status deployment/robrowser -n ragnarok

