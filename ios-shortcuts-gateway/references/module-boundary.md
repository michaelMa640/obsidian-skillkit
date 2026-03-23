# Module Boundary

## Goal

Define the exact responsibility boundary of `ios-shortcuts-gateway`.

## In scope

- expose a local HTTP endpoint
- accept mobile-originated requests over Tailscale
- authenticate requests with a bearer token
- validate request JSON
- route to a fixed internal action
- return structured mobile-safe results

## Out of scope

- direct execution of arbitrary shell commands from clients
- direct exposure of raw debug logs to mobile clients
- direct exposure of auth or cookie files
- replacing `obsidian-clipper`
- replacing `obsidian-analyzer`

## Dependency model

This module depends on:

- local Windows machine
- Tailscale connectivity
- OpenClaw or equivalent local task runner
- existing `obsidian-clipper`
- existing `obsidian-analyzer`

It should not own or duplicate those components.

## Fixed handoff model

### `action = clip`

The gateway should forward to the clipping workflow only.

### `action = analyze`

The gateway should forward to:

1. clipping workflow
2. analyzer workflow

or directly to analyzer only when an explicit future mode supports trusted existing clipping references.

## Security boundary

The gateway must be treated as:

- a private-network entrypoint
- not a public API
- not a general-purpose automation shell

## MVP completion criteria

Phase 1 is complete when:

- the gateway exists as an independent module directory
- its responsibilities are documented
- its dependencies are documented
- its allowed actions are documented
