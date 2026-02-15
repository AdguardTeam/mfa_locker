# Deployment

This guide covers the deployment configuration, infrastructure requirements, and
runtime settings for running this application in production.

## Environment Variables

<!--
  List all environment variables required to run the application.
  Include the variable name, purpose, whether it's required, and an example.
-->

| Variable | Purpose | Required | Example |
| --- | --- | --- | --- |
| `DATABASE_URL` | <!-- Database connection string --> | Yes | `postgresql://user:pass@host:5432/db` |
| `REDIS_URL` | <!-- Redis connection string --> | No | `redis://localhost:6379` |
| `SECRET_KEY` | <!-- Application secret for signing --> | Yes | `your-secret-key-here` |

<!--
  Security note: Never commit actual secrets to the repository.
  Use environment variables or a secrets manager in production.
-->

## Infrastructure Dependencies

<!--
  Document the external systems required to run the application.
  Include connection configuration and version requirements.
-->

### Database

<!--
  Describe the database requirements.
  Example:
  - **Type**: PostgreSQL 15+
  - **Connection**: Via `DATABASE_URL` environment variable
  - **Migrations**: Run `npm run db:migrate` before first start
-->

- **Type**: <!-- e.g., PostgreSQL 15+, MySQL 8+, MongoDB 6+ -->
- **Connection**: <!-- How to configure the connection -->
- **Initialization**: <!-- Any setup required before first run -->

### Cache / Message Queue

<!--
  Describe cache or message queue requirements if applicable.
  Remove this section if not needed.
-->

- **Type**: <!-- e.g., Redis 7+, Memcached, RabbitMQ -->
- **Connection**: <!-- How to configure the connection -->
- **Purpose**: <!-- What it's used for: caching, sessions, job queue -->

## Integrations

<!--
  Document external service integrations and their configuration.
  Include the service name, purpose, and required configuration.
-->

### External APIs

<!--
  List external APIs the application connects to.
  Example:
  - **Stripe**: Payment processing, requires `STRIPE_API_KEY`
  - **SendGrid**: Email delivery, requires `SENDGRID_API_KEY`
-->

| Service | Purpose | Configuration |
| --- | --- | --- |
| <!-- Service name --> | <!-- What it's used for --> | <!-- Required env vars --> |

### Authentication Providers

<!--
  Document OAuth/SSO providers if applicable.
  Remove this section if not needed.
-->

- **Provider**: <!-- e.g., Google OAuth, Auth0, Okta -->
- **Configuration**: <!-- Required credentials and callback URLs -->

## Error Reporting

<!--
  Document error reporting and monitoring configuration.
-->

### Sentry

<!--
  If using Sentry, document the configuration.
  Remove this section if not using Sentry.
-->

- **DSN**: Set via `SENTRY_DSN` environment variable
- **Environment**: Set via `SENTRY_ENVIRONMENT` (e.g., `production`, `staging`)
- **Release**: <!-- How releases are tracked, e.g., git commit SHA -->

<!--
  Additional Sentry options:
  - Sample rate for performance monitoring
  - Ignored errors or transactions
  - Custom tags or context
-->

## Logging

<!--
  Document where logs are written and how to configure logging.
-->

### Log Output

- **Location**: <!-- e.g., stdout/stderr, file path, log aggregator -->
- **Format**: <!-- e.g., JSON, plain text, structured -->
- **Level**: <!-- How to configure log level, e.g., LOG_LEVEL env var -->

<!--
  Example:
  - **Location**: stdout (for container environments)
  - **Format**: JSON (for log aggregation)
  - **Level**: Controlled by `LOG_LEVEL` env var (debug, info, warn, error)
-->

### Log Aggregation

<!--
  If logs are sent to an aggregation service, document it here.
  Remove this section if not applicable.
-->

- **Service**: <!-- e.g., Datadog, Splunk, ELK Stack -->
- **Configuration**: <!-- Required setup -->

## Health Checks

<!--
  Document health check endpoints for monitoring and orchestration.
  Remove this section if not applicable.
-->

| Endpoint | Purpose | Expected Response |
| --- | --- | --- |
| `/health` | Liveness check | `200 OK` |
| `/ready` | Readiness check | `200 OK` when ready to serve traffic |

<!--
  Describe what each health check verifies:
  - Liveness: Application is running
  - Readiness: Application can serve requests (DB connected, etc.)
-->

## Additional Resources

<!--
  Link to related documentation.
-->

- [README.md](README.md) - Project overview
- [DEVELOPMENT.md](DEVELOPMENT.md) - Development setup
- [AGENTS.md](AGENTS.md) - AI agent instructions
