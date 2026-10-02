---
aliases: [Async testing standard, pytest-asyncio requirement]
tags: [agent-rule]
entities: [Python, pytest, async, pytest-asyncio]
communities: [Coding Standards, Agent Procedural Memory]
status: scaffolded
---
[[AGNT.00.00]]

# AGNT.11.02 Async Python testing requires pytest-asyncio for event loop management

**Example:** This illustrates scoped procedural memory from
[[JRNL/AGNT/2026-04-24-1500|the sample initialization session]]. It does not
establish a preference for the current user.

**Illustrative rule:** In a project using pytest-asyncio, keep its configured
event-loop behavior when adding asynchronous tests.
