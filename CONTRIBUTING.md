# Contributing to vncaa

Thank you for your interest in contributing to vncaa! This document provides guidelines for contributing to the project.

## Getting Started

### Prerequisites

- Rust (via [rustup](https://rustup.rs/))
- Linux environment (Arch Linux recommended)
- Claude Code installed and authenticated
- TigerVNC or compatible VNC server
- noVNC (for web client)
- Docker (optional, for testing containerized builds)

### Development Setup

1. Fork and clone the repository:
```bash
git clone https://github.com/yourusername/vncaa.git
cd vncaa
```

2. Build the project:
```bash
cargo build
```

3. Run tests:
```bash
cargo test
```

## Running Locally

```bash
# Setup Claude Code authentication
claude setup-token
export CLAUDE_CODE_OAUTH_TOKEN=sk-...

# Run vncaa
cargo run -- /path/to/repo 1024x1024 8080
```

## Making Changes

### Code Style

- Follow standard Rust formatting: `cargo fmt`
- Run clippy before submitting: `cargo clippy -- -D warnings`
- Write tests for new functionality
- Keep functions focused and well-documented

### Testing

- Add unit tests for new functions in `src/main.rs`
- Ensure all tests pass: `cargo test`
- Test manually with actual VNC connections when changing display/networking code

### Commit Messages

- Use clear, descriptive commit messages
- Start with a verb in present tense (e.g., "Add", "Fix", "Update")
- Reference issue numbers when applicable

## Submitting Changes

1. Create a new branch for your feature or fix:
```bash
git checkout -b feature/your-feature-name
```

2. Make your changes and commit them:
```bash
git add .
git commit -m "Add feature description"
```

3. Push to your fork:
```bash
git push origin feature/your-feature-name
```

4. Open a Pull Request:
   - Describe what changes you've made
   - Reference any related issues
   - Ensure CI tests pass

## Reporting Issues

When reporting bugs, please include:
- Your operating system and version
- Rust version (`rustc --version`)
- Steps to reproduce the issue
- Expected vs actual behavior
- Any relevant logs or error messages

For feature requests:
- Describe the use case
- Explain how it would benefit users
- Provide examples if applicable

## Code of Conduct

This project follows a Code of Conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## Questions?

Feel free to open an issue for questions about contributing or using vncaa.

## License

By contributing to vncaa, you agree that your contributions will be licensed under the MIT License.
