{ pkgs ? import <nixpkgs> { } }:

pkgs.callPackage ./setec.nix { }
