# Nix-Robotics-Book

nix.asap.systems/robotics

## What

This book is intended as an in-depth introduction to deploying robot code on real hardware. It is intended to be accessible to readers with a broad range of prior experience, from no familiarity to nix or linux systems, to embedded robotics wizards.

## Why?

An essential part of robotics is deploying your code to real hardware. Despite this, much research and work is done in a manner that is excessively disconnected from the hardware and operating system, leading to a very large gap in the robustness (and reproducibility) of many robotic systems relative to their potential. As with any system, a high level of control and understanding of every component is a prerequisite to troubleshooting and effectively extending it. This documentation exists to serve that purpose, because there is currently a lack of accessible best-practices and conceptual introductions to the concepts discussed here.

## Choices

This book is very opinionated, and presents best-practices for various tasks.

## Contributions

Feel free to open an issue discussing changes or additions. PRs are welcome, but it would be ideal to discuss large changes in an issue first.

---- sections

## What are we doing?

By running python, or even c, we are taking advantage of layers upon layers of abstraction from the real hardware.

Ideal: library/embedded os
Practical for hardware: linux

## Introduction To Nix

Nix is a _build system_ focused on reproducibility. What makes nix unique is its approach to reproducibility from first principles, which will be discussed below. There exist several in depth introductions to nix ([nix-pills](https://nixos.org/guides/nix-pills/), [nix.dev](https://nix.dev/)), which may be useful for learning more. This section intends to motivate nix and impart a workable understanding of it.

### The Problem Nix Solves

Many programs have a compilation step.

Many build systems exist, with the purpose of .

## Introduction To NixOS

- systemd
- boot
