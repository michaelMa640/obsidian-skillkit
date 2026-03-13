---
name: obsidian-analyzer
description: Turn an existing clipping note in Obsidian into structured knowledge. Use when OpenClaw should read a clipping and produce a learn-style summary or a short-content breakdown.
---

# Obsidian Analyzer

## Overview

Use this skill for the second stage of the workflow.

This skill assumes the source has already been clipped into Obsidian.
It reads that stored content and transforms it into a more valuable knowledge note.

Typical chain:
- user asks OpenClaw to analyze an existing clipping
- `obsidian-analyzer` reads the clipping note
- the skill chooses `learn` or `analyze`
- the skill calls the configured LLM path
- the result is written into a formal knowledge folder

## Responsibilities

`obsidian-analyzer` is responsible for:
- reading an existing clipping note
- choosing the correct analysis mode
- structuring the content for the model
- generating a knowledge note
- saving the result into the vault

It is not responsible for:
- initial web capture
- replacing the clipper
- running viral breakdown on long-form video or podcast content

## Analysis modes

### `learn`

Use for:
- articles
- educational videos
- podcast and Xiaoyuzhou episodes
- experience-sharing content

Goal:
- extract ideas
- capture methods and frameworks
- generate reusable study notes

### `analyze`

Use for:
- Xiaohongshu posts
- Douyin short videos
- other short-form content where expression and packaging matter

Goal:
- explain why the content works
- break down hook, structure, emotion, and trust signals

Do not use for:
- Bilibili long videos
- YouTube long videos
- Xiaoyuzhou and podcast long audio

## Obsidian output

Suggested targets:
- `Insights/` for `learn`
- `Breakdowns/` for `analyze`

Keep the output structured and source-linked.