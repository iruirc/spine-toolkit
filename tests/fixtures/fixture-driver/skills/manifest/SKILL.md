---
name: manifest
description: Driver manifest for the fixture driver. Data, not instructions — the blocks spine-toolkit reads to learn which tools drive an app, which targets they reach, and what each target supports.
---

# Fixture Driver Manifest

> This skill is **data**, not instructions. spine-toolkit reads the blocks below by invoking this
> skill; there is no procedure here to follow.

This is the minimal manifest a driver plugin declares to spine-toolkit, kept as a fixture:
`lint-driver-manifest.sh` validates copies of it, and `driver-contract.test.bats` binds it to the
vocabulary. Treat every value below as load-bearing — use it as a template for a real driver, not as
a stub to satisfy a grep.

The two targets differ on purpose, and the difference is the whole point of declaring capabilities
per target rather than per driver: `android-device` reaches the hardware that `android-emulator` only
simulates, so it carries `push`, `biometrics` and `camera`, and the emulator does not. A validator
planning a run reads that difference and hands a human what the emulator cannot show.

## Driver

`namespace` lists the prefixes this server's tools plausibly carry in a session's tool list — the
key a user writes in their MCP configuration is arbitrary, so a driver names the ones it is likely
registered under and the resolver takes the first that is actually present. Named neutrally and not
after any real server: core ships no ecosystem knowledge, and a fixture is read as part of the
contract.

namespace = neutral, neutral-devices

## Targets

The surfaces this driver drives, bare, from core's surface vocabulary. `android-emulator` and
`android-device` differ in exactly the way the per-surface shape exists for: the emulator simulates
what the device has in hardware.

android-emulator
android-device

## Capabilities: android-emulator

launch stop install reset_state
ui_tree find assert screenshot video logs
tap type swipe gesture key
deeplink background permissions alerts viewport locale webview
a11y_audit visual_baseline performance
record_replay multi_device

## Capabilities: android-device

launch stop install reset_state
ui_tree find assert screenshot video logs
tap type swipe gesture key
deeplink background permissions alerts viewport locale webview
push biometrics camera location network_conditions
a11y_audit visual_baseline performance
record_replay multi_device

## Procedure

The text tree before a screenshot: it is an order of magnitude cheaper, and a tree answers most
questions a screenshot is reached for.

The target is chosen at run time from what is actually attached, never pinned to a constant — a
manifest that names one device is wrong on every machine but its author's.

Leave the app stopped when the run ends. Do not reset device defaults unless the task asked for it:
the next run inherits whatever this one left.
