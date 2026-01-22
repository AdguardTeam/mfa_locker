# Security Policy

## Reporting Security Vulnerabilities

AdGuard Software Limited takes the security of our software products seriously. If you believe you have found a security vulnerability in MFA Locker, we encourage you to let us know right away.

### How to Report a Security Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to: **security@adguard.com**

Please include the following information in your report:

- Type of issue (e.g., cryptographic weakness, insecure local storage, key/secret exposure, authentication bypass, memory disclosure, platform Keychain/Keystore misuse, etc.)
- Full paths of source file(s) related to the manifestation of the issue
- The location of the affected source code (tag/branch/commit or direct URL)
- Any special configuration required to reproduce the issue
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit it


### Response Timeline

- We will acknowledge receipt of your vulnerability report within 3 business days
- We will send you regular updates about our progress
- If the issue is confirmed, we will release a patch as soon as possible depending on complexity

### Disclosure Policy

- We ask that you do not publicly disclose the vulnerability until we have had a chance to address it
- We will credit you in the security advisory (unless you prefer to remain anonymous)
- We aim to release security fixes in a timely manner and will coordinate the disclosure with you

## Supported Versions

We recommend using the latest version of MFA Locker. Security updates will be applied to the current major version.

## Security Best Practices

When using MFA Locker:

1. **Keep dependencies updated**: Regularly update Flutter/Dart SDK and all dependencies
2. **Use strong passwords**: Enforce strong password policies for users
3. **Enable biometric authentication**: When available, use biometric authentication for additional security
4. **Secure storage location**: Store the encrypted vault file in a secure location with appropriate file permissions
5. **Regular backups**: Maintain secure backups of your encrypted data
6. **Monitor auto-lock settings**: Configure appropriate auto-lock timeouts for your security requirements

## Known Security Considerations

- MFA Locker stores encrypted data locally. The security of the data depends on the strength of the user's password and the security of the device
- Biometric authentication delegates to platform-specific secure enclaves (TPM/Secure Enclave). The security depends on the platform implementation
- The library uses industry-standard encryption algorithms (AES-GCM, PBKDF2, HMAC-SHA256)
- Memory is securely wiped using `ErasableByteArray` to prevent sensitive data from remaining in memory

For more technical details about the security architecture, see [docs/MFA_Locker.md](docs/MFA_Locker.md).
