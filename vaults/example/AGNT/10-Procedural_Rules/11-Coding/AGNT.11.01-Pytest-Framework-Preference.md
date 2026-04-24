---
aliases: [Python testing preference, pytest vs unittest]
tags: [agent-rule]
entities: [Python, pytest, unittest, testing]
communities: [Coding Standards, Agent Procedural Memory]
status: crystallized
---
[[AGNT.00.00]]

# AGNT.11.01 Pytest is the preferred Python testing framework

**Observation:** During session [[JRNL/AGNT/2026-04-24-1430]], the user rejected a `unittest` implementation, citing `pytest` as the project standard for its more expressive syntax and ecosystem support.

**Rule:** For all Python development in this vault, use `pytest` for unit and functional testing. Avoid `unittest` unless specifically required by legacy dependencies.
