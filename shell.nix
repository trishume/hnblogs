{ ... }:
let
pkgs = import <nixpkgs> {};
version = "1.1";
env = pkgs.bundlerEnv rec {
  name = "hnblogs-${version}-gems";

  ruby = pkgs.ruby;
  inherit version;
  # expects Gemfile, Gemfile.lock and gemset.nix in the same directory
  gemfile = ./Gemfile;
  lockfile = ./Gemfile.lock;
  gemset = ./gemset.nix;
};

in pkgs.stdenv.mkDerivation {
  name = "hnblogs-${version}";

  inherit env;
  inherit version;

  buildInputs = with pkgs; [
    ruby
    bundix
    # bundler
    # curl
    env
  ];


  # gemConfig = pkgs.lib.recursiveUpdate pkgs.defaultGemConfig {
  #   typhoeus = spec: {
  #    buildInputs = [ (pkgs.getLib pkgs.curl) ];
  #   };
  # };

  shellHook = with pkgs; ''
    export LD_PRELOAD="${pkgs.stdenv.lib.makeLibraryPath [ curl ]}/libcurl.so.4"
    echo $LD_PRELOAD
  '';
}
