# Security Contract

## Goal

Define the minimum security boundary for `ios-shortcuts-gateway`.

The gateway is a private-network task entrypoint, not a public automation shell.

## Network exposure rules

### Allowed

- listen on a Tailscale private IP
- listen on localhost when a trusted local proxy is used

### Not allowed for MVP

- listen on `0.0.0.0`
- expose the service directly to the public internet
- expose the service through generic unauthenticated port forwarding

## Authentication

The gateway must require a bearer token for every task request.

Required request header:

```http
Authorization: Bearer <SECRET_TOKEN>
```

Rules:

- token must be compared exactly
- missing token returns `401`
- invalid token returns `401`
- token value must not be logged in plaintext

## Allowed capability surface

The gateway may expose only fixed business actions:

- `clip`
- `analyze`

The gateway must not expose:

- arbitrary shell execution
- arbitrary PowerShell argument passthrough
- arbitrary file reads
- arbitrary vault browsing
- arbitrary debug bundle download

## Input validation boundary

The gateway must reject:

- empty `source_text`
- unsupported `action`
- oversized payloads

Recommended request limit:

- `source_text` <= `5000` characters

## Script execution boundary

The gateway must internally map:

- `clip` -> clipping workflow
- `analyze` -> clipping + analyzer workflow

It must not allow the client to choose:

- script path
- vault path
- debug directory
- shell fragment
- arbitrary environment variables

## Sensitive data rules

The gateway must never return or log:

- cookie contents
- storage state contents
- auth file contents
- raw support-bundle contents
- full raw debug logs by default
- bearer token

## Result exposure rules

The gateway may return only mobile-safe summaries such as:

- status
- Chinese summary message
- failed step
- short note path summary
- auth refresh command when needed

It should avoid returning unnecessary absolute local paths unless explicitly needed for trusted local debugging.

## Logging boundary

The gateway may log:

- timestamp
- action
- request id
- success / failure status
- failed step

The gateway should avoid logging:

- full source text unless needed for local debugging
- auth file locations in mobile-facing output
- raw request headers

## Failure guidance boundary

When a request fails:

- return a concise mobile-safe error
- instruct the user to retrieve local `support-bundle/` if needed

Do not inline raw debug artifacts into the HTTP response.

## MVP completion criteria

Phase 3 security work is complete when:

- bearer token requirement is documented
- allowed listening scope is documented
- disallowed exposure patterns are documented
- sensitive data rules are documented
