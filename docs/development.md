# Development Guide

## Overview

This guide provides information for developers working with the robrowser_docker project, including setup, contribution guidelines, and development practices.

## Project Structure

```
robrowser_docker/
├── client/                 # Client files (DATA.INI, GRF files)
├── database/               # Database configuration and data
├── docker-compose-common.yml  # Common Docker Compose configuration
├── docker-compose-rathena.yml # Rathena-specific Docker Compose
├── docker-compose-hercules.yml # Hercules-specific Docker Compose
├── hercules/               # Hercules server files
│   ├── Dockerfile          # Hercules server Dockerfile
│   ├── docker-entrypoint.sh # Hercules entrypoint script
│   └── repository_override/ # Override files for Hercules
├── k8s/                    # Kubernetes configurations
├── rathena/                # Rathena server files
│   ├── Dockerfile          # Rathena server Dockerfile
│   ├── entrypoint.sh       # Rathena entrypoint script
│   └── repository_override/ # Override files for Rathena
├── robrowser/              # roBrowser files
│   ├── Dockerfile          # roBrowser Dockerfile
│   ├── entrypoint.sh       # roBrowser entrypoint script
│   ├── index.html.template # Template for HTML generation
│   └── repository_override/ # Override files for roBrowser
├── scripts/                # Deployment scripts
├── start.sh                # Main deployment script
└── docs/                   # Documentation files
```

## Development Setup

### Prerequisites

- Git
- Docker and Docker Compose
- Kubernetes cluster (for Kubernetes development)
- Helm (for MariaDB operator)
- Basic understanding of containerization and orchestration

### Local Development Environment

1. **Clone Repository**
   ```bash
   git clone https://github.com/raiken-mf/robrowser_docker.git
   cd robrowser_docker
   ```

2. **Prepare Client Files**
   Place your client files in the `client/` directory:
   - Ensure `DATA.INI` is all caps
   - Add required GRF files to appropriate subdirectories

3. **Configure Environment**
   ```bash
   cp .env-tmpl .env
   # Edit .env to set your preferences
   ```

4. **Build and Run**
   ```bash
   # Using Docker Compose
   ./start.sh
   
   # Or for specific server
   ./start.sh hercules
   ```

## Contributing

### Code Style Guidelines

1. **Consistent Formatting**
   - Follow existing code style
   - Use consistent naming conventions
   - Maintain proper indentation

2. **Documentation**
   - Document all new features
   - Update existing documentation
   - Follow the documentation structure

3. **Security**
   - Follow security best practices
   - Never commit sensitive information
   - Use environment variables for configuration

### Pull Request Process

1. **Create Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make Changes**
   - Implement your feature or fix
   - Follow existing code patterns
   - Add tests if applicable

3. **Update Documentation**
   - Update relevant documentation files
   - Ensure documentation reflects code changes
   - Follow the documentation structure

4. **Test Changes**
   - Test locally with Docker Compose
   - Test in Kubernetes if applicable
   - Verify security configurations

5. **Submit Pull Request**
   - Push to your fork
   - Create pull request against main branch
   - Include description of changes

### Commit Guidelines

Follow conventional commits format:
- `feat: Add new feature`
- `fix: Resolve bug`
- `docs: Update documentation`
- `security: Improve security`
- `chore: Routine maintenance`

## Testing

### Unit Testing

The project uses the following testing approaches:

1. **Integration Tests**
   - Test Docker Compose deployments
   - Test Kubernetes deployments
   - Verify service connectivity

2. **Security Tests**
   - Verify non-root execution
   - Check capability restrictions
   - Validate security contexts

3. **Functional Tests**
   - Test server startup
   - Verify database connection
   - Validate client connectivity

### Testing Scripts

The project includes test scripts in the `scripts/` directory:
- `test-deployment.sh` - Test deployment scenarios
- `test-security.sh` - Test security configurations
- `test-integration.sh` - Test integration between components

## Development Best Practices

### Container Development

1. **Minimal Images**
   - Use Alpine base images
   - Remove unnecessary packages
   - Optimize layer caching

2. **Security**
   - Run as non-root user
   - Drop unnecessary capabilities
   - Use read-only filesystems where possible

3. **Performance**
   - Optimize build processes
   - Minimize image sizes
   - Use multi-stage builds

### Script Development

1. **Error Handling**
   - Implement proper error handling
   - Use `set -e` for scripts
   - Validate inputs

2. **Security**
   - Avoid hardcoded credentials
   - Use environment variables
   - Sanitize inputs

3. **Maintainability**
   - Write clear comments
   - Use descriptive variable names
   - Follow consistent formatting

## Debugging

### Docker Compose Debugging

1. **View Logs**
   ```bash
   docker logs <container-name>
   ```

2. **Access Containers**
   ```bash
   docker exec -it <container-name> /bin/sh
   ```

3. **Monitor Resources**
   ```bash
   docker stats
   ```

### Kubernetes Debugging

1. **View Logs**
   ```bash
   kubectl logs <pod-name>
   ```

2. **Access Pods**
   ```bash
   kubectl exec -it <pod-name> -- /bin/sh
   ```

3. **Describe Resources**
   ```bash
   kubectl describe pod <pod-name>
   ```

## Performance Optimization

### Container Optimization

1. **Layer Caching**
   - Order Dockerfile instructions strategically
   - Group frequently changing instructions
   - Use .dockerignore

2. **Resource Management**
   - Set appropriate resource limits
   - Monitor resource usage
   - Optimize memory allocation

### Code Optimization

1. **Efficient Scripts**
   - Minimize subprocess calls
   - Use efficient string operations
   - Cache expensive operations

2. **Database Optimization**
   - Optimize SQL queries
   - Use appropriate indexes
   - Monitor query performance

## Release Process

### Versioning

The project follows semantic versioning principles:
- Major version for breaking changes
- Minor version for new features
- Patch version for bug fixes

### Release Checklist

1. **Code Review**
   - All code reviewed
   - Security audit performed
   - Documentation updated

2. **Testing**
   - All tests pass
   - Integration tests successful
   - Security tests passed

3. **Release Preparation**
   - Update version numbers
   - Update changelog
   - Tag release

4. **Publish**
   - Push to main branch
   - Create GitHub release
   - Update documentation

## Continuous Integration

### CI Pipeline

The project includes CI pipeline configuration:
- Automated testing on code changes
- Security scanning of container images
- Documentation validation
- Deployment verification

### CI Configuration

The CI pipeline includes:
- Code linting and formatting
- Security vulnerability scanning
- Unit and integration testing
- Documentation generation
- Artifact publishing

## Community Guidelines

### Communication

1. **Issues**
   - Report bugs with clear reproduction steps
   - Request features with detailed descriptions
   - Provide feedback on existing issues

2. **Discussions**
   - Participate in development discussions
   - Share knowledge and experiences
   - Help other contributors

3. **Support**
   - Provide support in forums
   - Answer questions from users
   - Contribute to documentation

### Code of Conduct

All contributors are expected to follow the project's code of conduct:
- Be respectful and inclusive
- Provide constructive feedback
- Focus on technical merit
- Maintain professional standards