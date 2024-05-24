# 2. Use deno/typscript for all scripting and bazel adjacent work

Date: 2024-05-24

## Status

Accepted

## Context

While Bazel is the main tool being used to build the project, there are many tasks that are not well suited to Bazel. These include:

- Preprocessing files
- Generating code
- Doing one-off tasks to get things ready for Bazel

I started by using Golang as a way to not need to have external dependencies, but it's not a great language for scripting. I started using deno since it supports TypeScript and has a mechanism for importing modules from the web without needing to set up a package manager.

## Decision

For everything that can't be done with Bazel, use deno/TypeScript.

## Consequences

- Deno would need to be installed at some point during the build process
- This will cause a split in where to put certain logic but I'm hoping defaulting to Bazel will be enough to make it clear where to put things
