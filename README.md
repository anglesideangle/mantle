# mantle

Mantle is a framework for using nixos and systemd to build and deploy
image-based emedded linux systems. It provides a hybrid deployment mechanism,
allowing for both high reliability a/b updates and fast overlay-based updates.
Building and deploying custom embedded linux images is usually a daunting
task, and mantle intends to make it more approachable with examples and very
comprehensive documentation.

If your deployment process looks like:

1. `ssh $ROBOT_IP`
2. `cd $WORKSPACE_DIR`
3. pull or directly edit changes
4. build your new changes (on the robot)
5. launch your program(s) via ros2 launch or (god bless your soul) tmux

...you may be entitled to a deployment system that is well designed. Use this
instead!

<!-- Also see [intro] [implementation] [security] -->

## Motivation

Deploying and running programs on a computer involves many layers of abstraction
between your program and the hardware. These abstractions are helpful, but
also introduce complexity. On a raspberry pi running linux, for example, your
program(s) account for a small fraction of the code that must be compiled and
deployed in order for the entire system to run, the rest being device drivers,
filesystems, network configuration, IO management, service management, etc. It's
not enough to only manage your program source code, you should also manage the
entire underlying system.

Nix and NixOS are uniquely well-suited to provide a declarative and
(best-effort) reproducible environment that can be used to deploy


## Intro?

Nix is a powerful meta build system that runs builds ("derivations") in a
sandbox with access only to other programs built with nix. These builds can be
arbitrary processes, including other builds systems or scripts, such as cmake,
cargo, etc. It is uniquely well-suited to play nicely with external ecosystems.
Each program is built

NixOS is a framework using nix to build full linux systems. It is capable of building system images.

Nix
is a build system that reasons about. NixOS is a tool that allows .

Thus, in order to deploy a program to a computer, you must
also manage everything below it.

<!-- Robots, for example, are often ran on top of a full linux system, with a specific. -->

For "appliance systems," where the program has one use-case, it is desirable to .

While some domains allow distributing your program as a container, this is not
the case for "appliance" systems, where you . running programs on real hardware, having control over all of
these layers is important.

## Usage

```sh
nix run .#deploy-overlay
```

## Limitations

- module system

## Standing on the shoulders of giants

The mantle project contributes very little on its own. It leans very heavily on tools already implemented in nixos and systemd. See:
- [NixOS: A Purely Functional Linux Distribution](https://edolstra.github.io/pubs/nixos-jfp-final.pdf)
- [Fitting Everything Together](https://0pointer.net/blog/fitting-everything-together.html)
- [Immutable Systems: NixOS + systemd-repart + systemd-sysupdate](https://x86.lol/generic/2024/08/28/systemd-sysupdate.html)
