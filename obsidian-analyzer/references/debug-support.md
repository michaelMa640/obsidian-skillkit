# Analyzer Debug Support

## Purpose

This document explains which analyzer debug files matter and what users should upload when reporting a problem.

## Default debug location

The debug root is controlled by:

- `analyzer.default_debug_directory`

Each run creates a timestamped subfolder under that root.

## Core artifacts

- `analyzer-payload.json`
  normalized input assembled from the clipping note and sidecars
- `analysis-input.json`
  final analysis object used by the renderer
- `llm-request.json`
  sanitized request payload sent to the configured provider
- `llm-response.json`
  sanitized provider response
- `run-analyzer.json`
  structured run result
- `run-analyzer-summary.txt`
  human-readable run summary

## Shareable package

Use `support-bundle/` as the first-line support package.

It contains sanitized copies of the most important files so issues can be debugged without exposing local vault paths.

## What to upload to an issue

Preferred:

- `support-bundle/`

If the problem cannot be reproduced from the shareable bundle, upload the full debug directory as a second step.

## Typical failure reading

- `failed_step = config_load`
  local config is missing or invalid
- `failed_step = input_resolve`
  note path or capture JSON path is missing
- `failed_step = payload_build`
  clipping note or sidecar parsing failed
- `failed_step = llm_invoke`
  real model call failed or the run fell back to mock output
- `failed_step = note_render`
  final markdown rendering or vault write failed
