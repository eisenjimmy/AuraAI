# Security policy

## Supported version

Security fixes are applied to the latest native macOS release and the `main` branch.

## Reporting a vulnerability

Please use [GitHub private vulnerability reporting](https://github.com/eisenjimmy/AuraAI/security/advisories/new). Do not open a public issue for path traversal, permission bypass, secret exposure, prompt-injection execution, unsafe document generation, or macOS control vulnerabilities.

Include reproduction steps, affected version, expected impact, and a minimal proof of concept without private data. Allow maintainers reasonable time to investigate before public disclosure.

## Security boundary

Aura AI provides path validation, permission prompts, local cloud redaction, tool-loop limits, and post-write validation. It is not a hardened VM or operating-system sandbox. A user-approved shell command runs with the permissions of the current macOS user. Review every approval request and use trusted models and providers.
