{ ... }:
{
  projectRootFile = "flake.nix";

  programs.nixfmt.enable = true;
  programs.dart-format.enable = true;
  programs.prettier.enable = true;

  settings.excludes = [
    # git submodule — owns its own treefmt setup
    "conformance/**"
    # Dart build artifacts (AOT perf suite, etc.)
    ".dart_tool/**"
    "build/**"
    "node_modules/**"
  ];
}
