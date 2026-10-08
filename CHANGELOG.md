# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Fixed

- `start.sh`: Install Docker only when it is missing, then verify Docker Compose and daemon availability before starting services.
- `scripts/k8s-all.sh`: Require confirmation before resetting an existing namespace; fail safely on namespace lookup or deletion errors, and wait for deletion to complete before deploying.
