# Getting Started

Mantle is a nix framework, and as such depends on nix. Basic familiarity
with the nix language and cli are necessary to understand and use mantle.
[nix.dev](https://nix.dev/) provides installation instructions and a useful
introduction to the language, which will be helpful. To summarize _very
briefly_:

## Nix Speedrun

```nix
2 + 2
# 4
```

```nix
let
  x = 2;
  y = x + 1;
in
y
# 3
```

```nix
let
  f = num: num + 1;
  x = 2;
in
f x
# 3
```

## Examples

The [examples](../examples) directory contains several example projects using
mantle, including for deployong on a jetson orin and a raspberry pi, and (soon)
will include usage examples for deploying projects from various ecosystems.
