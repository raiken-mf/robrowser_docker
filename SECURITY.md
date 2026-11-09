# Security policy

## Reporting vulnerabilities

Do not publish suspected vulnerabilities, credentials or exploit details in
public issues, discussions or pull requests. Use the repository's GitHub Security
tab and **Report a vulnerability** if private reporting is available. Its
availability has not been verified; if the button is absent, contact a maintainer
privately to arrange a confidential channel before sharing details. Maintainers
should enable private vulnerability reporting or publish a verified private contact.

Include the affected revision and component, impact, minimal reproduction and
possible mitigation. Redact credentials and personal data. Test only systems you
own or are authorized to assess, and coordinate disclosure with maintainers.
No response deadline or supported-version guarantee is currently established.

## Known boundaries

- Replace template and compatibility-default credentials before deployment.
  The rAthena database client receives a password in its process arguments.
- Vite host restrictions and disabled CORS are not authentication or network
  isolation. Protect exposed services and transport appropriately.
- Some Kubernetes workloads require writable root filesystems. MariaDB's image
  tag is not digest-pinned; image layers may retain build-time Git metadata.
- Existing Trivy gates cover changed published images and fixable HIGH/CRITICAL
  findings; they do not prove the absence of vulnerabilities or rescan unchanged
  images on every change. Hercules is scanned on affected PRs but is not published.

See [docs/security.md](docs/security.md) for deployment controls, secrets,
release scanning and operational limitations.