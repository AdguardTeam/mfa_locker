# Contributing to MFA Locker

Thank you for your interest in MFA Locker!

## Contribution Policy

**Please note:** This is a source-available project maintained by AdGuard Software Limited. We do not accept pull requests from external contributors at this time.

Development and maintenance are handled internally by the AdGuard team to ensure code quality, security standards, and alignment with our product roadmap.

## How You Can Help

While we cannot accept code contributions, we highly value community feedback:

### Reporting Bugs

If you find a bug, please open an issue on our [GitHub issue tracker](https://github.com/AdguardTeam/mfa_locker/issues) with:

- A clear and descriptive title
- Steps to reproduce the issue
- Expected behavior
- Actual behavior
- Your environment (OS, Flutter/Dart version)
- Any relevant logs or screenshots

### Suggesting Features

Feature suggestions are welcome! Please open an issue with:

- A clear and descriptive title
- Detailed description of the proposed feature
- Explanation of why this feature would be useful
- Your use case and examples

### Improving Documentation

If you find errors or areas for improvement in the documentation, please open an issue describing the problem.

## Using the Code

You are free to:
- Use this library in your projects (subject to the MIT License)
- Fork the repository for your own use
- Study the code and learn from it
- Report issues and suggest improvements

## Development Setup (for reference)

If you want to build or test the project locally:

1. Install [fvm](https://fvm.app/):
   ```bash
   dart pub global activate fvm
   ```

2. Setup Flutter version:
   ```bash
   fvm install
   fvm use
   ```

3. Install dependencies:
   ```bash
   fvm flutter pub get
   cd example && fvm flutter pub get
   ```

4. Run tests:
   ```bash
   fvm flutter test
   ```

### Security

If you discover a security vulnerability, please **do not** open a public issue. Instead, email us at security@adguard.com.

## License

By contributing to MFA Locker, you agree that your contributions will be licensed under the MIT License.
