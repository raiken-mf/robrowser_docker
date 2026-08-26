#!/usr/bin/env bash
set -e

# Namespace & PVC sicherstellen
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/pvc-client-data.yaml

# Helper-Pod starten
kubectl apply -f k8s/pvc-helper.yaml

# Warten bis der Pod bereit ist
kubectl wait --for=condition=Ready pod/client-data-loader -n ragnarok --timeout=60s

# Zielverzeichnisse im PVC vorbereiten
kubectl exec -n ragnarok client-data-loader -- mkdir -p /data/resources /data/BGM /data/AI

# Optional: Vorhandene Daten vorher leeren für einen sauberen Stand
kubectl exec -n ragnarok client-data-loader -- rm -rf /data/resources/* /data/BGM/* /data/AI/*

# Lokale Daten relativ ins Longhorn-Volume schieben
echo "==> Kopiere Client-Ressourcen..."
kubectl cp ./client/resources/. ragnarok/client-data-loader:/data/resources/
kubectl cp ./client/BGM/. ragnarok/client-data-loader:/data/BGM/
kubectl cp ./client/AI/. ragnarok/client-data-loader:/data/AI/

# Inhalt zur Kontrolle listen
kubectl exec -n ragnarok client-data-loader -- ls -la /data/resources

# Helper-Pod wieder abbauen (Daten bleiben im PVC)
kubectl delete -f k8s/pvc-helper.yaml
echo "==> Initialisierung der Client-Daten abgeschlossen!"
