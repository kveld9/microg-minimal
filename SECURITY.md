# Security Policy

## Supported Versions

Only the latest tagged release on the `main` branch receives security fixes.

| Version | Supported |
| :--- | :--- |
| Latest tagged release (`main`) | Yes |
| Older releases | No |

## Reporting a Vulnerability

Report suspected vulnerabilities via GitHub Private Vulnerability Reporting (Security tab, Report a vulnerability). Do not open public issues, discussions, or pull requests for suspected vulnerabilities.

Include: affected module version tag, upstream microG tag from versions.env, device/Android/Manager environment, minimal reproduction steps, relevant log excerpt.

Do not include secrets: private keys, tokens, keystores, serials, IMEI, MACs.

## Scope and Boundaries

This repository publishes a client-side systemless module and assembly scripts. It operates no backend servers or accounts. Out of scope: proprietary Google Play Services redistribution, signature spoofing bypasses beyond what microG documents.

## Response Process

Triaged on a best-effort basis. Allow reasonable time before public disclosure.
