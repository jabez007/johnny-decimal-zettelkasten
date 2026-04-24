---
aliases: [Async testing standard, pytest-asyncio requirement]
tags: [agent-rule]
entities: [Python, pytest, async, pytest-asyncio]
communities: [Coding Standards, Agent Procedural Memory]
status: crystallized
---
[[AGNT.00.00]]

# AGNT.11.02 Async Python testing requires pytest-asyncio for event loop management

**Observation:** In [[JRNL/AGNT/2026-04-24-1430]], code failures occurred because the agent attempted to run async tests without the `pytest-asyncio` plugin, leading to unhandled coroutine warnings.

**Rule:** When implementing or modifying asynchronous Python code, the `pytest-asyncio` plugin must be present in the environment to ensure correct event-loop lifecycle management during test execution.
