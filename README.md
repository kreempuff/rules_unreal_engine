# Bazel rules for Unreal Engine

## Goal

The goal of this project is to provide a set of Bazel rules to build Unreal Engine itself and Unreal Engine projects with Bazel.

### Motivation

I'm making my own game using Unreal. I have a background in Software Engineering/Ops and I found it difficult to navigate all the custom build scripts and tools that Unreal Engine uses.
I want it to be easier to build Unreal Engine and Unreal Engine projects in different environments (Linux, Windows, Mac, CI/CD, etc) without having to think about the ins
and outs of Unreal Engine's build system.

### Why Bazel?

[Bazel](https://bazel.build) is a build system that is designed to be fast, reliable, and reproducible. I know it well enough to be able to map Unreal Engine's build system to it.

### Why not use Unreal's build system?

Unreal Engine's build system is complex and not well documented (in my opinion). It's difficult to understand how to build Unreal Engine and Unreal Engine projects in different environments.

## Quick start

TODO

## Roadmap to 1.0

- [ ] Build Unreal Engine from source in Bazel
  - [x] Download a specific commit of Unreal Engine as a bazel repo rule
  - [x] Configure Unreal Engine (mimic `Setup.(bat|sh)` functionality)
    - [x] Download git dependencies
    - [x] Unpack git dependencies
  - [ ] Build a module of Unreal Engine in Bazel *(Phase 1.2)*
    - [ ] Design and implement `ue_module` Bazel rule
    - [ ] Write BUILD.bazel for Core module
    - [ ] Build Core module with Bazel
    - [ ] Build CoreUObject module (depends on Core)
  - [ ] Build Unreal Editor in Bazel *(Phase 1.3+)*
- [ ] Build and Package Unreal Engine projects in Bazel *(Phase 2)*
  - [ ] Design and implement `ue_project` Bazel rule
  - [ ] Generate BUILD files for Unreal Engine plugins
