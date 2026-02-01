# =============================================================================
# Caradoc Nix Flake
# =============================================================================
#
# Caradoc is a PDF parser and validator written in OCaml. This flake provides
# a development environment and package build for modern systems.
#
# =============================================================================
# COMPATIBILITY NOTES
# =============================================================================
#
# Caradoc was written for older OCaml versions and uses patterns that are
# incompatible with modern OCaml (4.09+):
#
# 1. MUTABLE STRINGS: OCaml made strings immutable in 4.02, and modern nixpkgs
#    compiles OCaml with -force-safe-string, which prevents using -unsafe-string.
#    Solution: We use an overlay to rebuild OCaml with --disable-force-safe-string
#
# 2. NEW WARNINGS TREATED AS ERRORS: The Makefile uses -warn-error +a which
#    turns all warnings into errors. Newer OCaml versions added warnings that
#    this code triggers:
#    - Warning 44: open-shadow-identifier (added in OCaml 4.09)
#    - Warning 67: unused-functor-parameter
#    - Warning 69: unused-field
#    - Warning 70: missing-mli
#    Solution: We patch the Makefile to disable these warnings
#
# =============================================================================
# HOW TO USE
# =============================================================================
#
# OPTION 1: Development Shell (recommended for development)
# ---------------------------------------------------------
#   nix develop
#
#   This enters an interactive shell with all dependencies available.
#   The Makefile is automatically patched on first entry.
#
#   Inside the shell:
#     make              # Build the caradoc binary
#     make test         # Run unit tests
#     make clean        # Clean build artifacts
#     ./caradoc --help  # Run the built binary
#
#   Result files:
#     ./caradoc         # Main executable (symlink to _build/src/main.native)
#     ./_build/         # Build directory with all compiled files
#
# OPTION 2: Nix Package Build (recommended for installation)
# ----------------------------------------------------------
#   nix build
#
#   This builds caradoc as a proper Nix package in an isolated environment.
#
#   Result files:
#     ./result/bin/caradoc  # The built executable (symlink to nix store)
#
#   To run directly without creating ./result symlink:
#     nix run . -- stats somefile.pdf
#
#   To install to your profile:
#     nix profile install .
#
# =============================================================================
# EXAMPLE USAGE
# =============================================================================
#
#   # Parse a PDF and show statistics
#   caradoc stats document.pdf
#
#   # Validate a PDF strictly
#   caradoc stats --strict document.pdf
#
#   # Show xref table
#   caradoc xref document.pdf
#
#   # Interactive UI mode
#   caradoc ui document.pdf
#
#   # Extract specific object
#   caradoc object --num 2 document.pdf
#
# =============================================================================

{
  description = "Caradoc - a PDF parser and validator written in OCaml";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # =====================================================================
        # OCaml Overlay
        # =====================================================================
        # Rebuild OCaml 4.14 with --disable-force-safe-string to allow the
        # -unsafe-string compiler flag. This is needed because caradoc uses
        # mutable string operations (s.[i] <- c) which were deprecated in
        # OCaml 4.02 and require -unsafe-string to compile.
        #
        # Without this overlay, you get:
        #   "OCaml has been configured with -force-safe-string: -unsafe-string
        #    is not available"
        # =====================================================================
        ocamlOverlay = final: prev: {
          ocaml-ng = prev.ocaml-ng // {
            ocamlPackages_4_14 = prev.ocaml-ng.ocamlPackages_4_14.overrideScope (ofinal: oprev: {
              ocaml = oprev.ocaml.overrideAttrs (old: {
                configureFlags = (old.configureFlags or []) ++ [ "--disable-force-safe-string" ];
              });
            });
          };
        };

        pkgs = import nixpkgs {
          inherit system;
          overlays = [ ocamlOverlay ];
        };

        ocamlPackages = pkgs.ocaml-ng.ocamlPackages_4_14;

        # =====================================================================
        # Makefile Patch Commands
        # =====================================================================
        # These sed commands patch the Makefile to:
        # 1. Disable warnings 44, 67, 69, 70 (not present in older OCaml)
        # 2. Add -unsafe-string flag to allow mutable string operations
        # =====================================================================
        makefilePatchCommands = ''
          sed -i \
            -e 's/-w,+a-3-4-32\.\.39/-w,+a-3-4-32..39-44-67-69-70/' \
            -e 's/-noautolink/-noautolink,-unsafe-string/' \
            Makefile
        '';

      in
      {
        # =====================================================================
        # Development Shell
        # =====================================================================
        # Enter with: nix develop
        #
        # Provides an interactive environment with all build tools and
        # dependencies. The Makefile is automatically patched on first entry.
        #
        # Commands available:
        #   make        - Build caradoc binary (output: ./caradoc)
        #   make test   - Run unit tests
        #   make clean  - Remove build artifacts
        # =====================================================================
        devShells.default = pkgs.mkShell {
          buildInputs = with ocamlPackages; [
            # OCaml toolchain
            ocaml           # The compiler (rebuilt with --disable-force-safe-string)
            ocamlbuild      # Build system used by caradoc
            findlib         # OCaml package manager (ocamlfind)
            menhir          # Parser generator for PDF grammar

            # OCaml libraries
            ounit           # Unit testing framework
            cryptokit       # Crypto and compression (includes Deflate for PDF streams)
            curses          # Terminal UI library for interactive mode
          ] ++ (with pkgs; [
            # System dependencies required by OCaml libraries
            zlib            # Compression library (for cryptokit/Deflate)
            gmp             # GNU Multiple Precision arithmetic (for cryptokit)
            pkg-config      # Helper for finding system libraries
            m4              # Macro processor (build dependency)
            ncurses         # Terminal handling (for curses bindings)
            gnused          # GNU sed for Makefile patching
          ]);

          shellHook = ''
            echo "========================================"
            echo "Caradoc Development Environment"
            echo "========================================"

            # Patch Makefile for modern OCaml compatibility (only once)
            if ! grep -q '\-44' Makefile 2>/dev/null; then
              ${makefilePatchCommands}
              echo "Patched Makefile for modern OCaml compatibility"
              echo ""
            fi

            echo "Commands:"
            echo "  make        - Build caradoc (output: ./caradoc)"
            echo "  make test   - Run unit tests"
            echo "  make clean  - Clean build artifacts"
            echo ""
            echo "Example:"
            echo "  ./caradoc stats test_files/positive/hello/hello.pdf"
            echo "========================================"
          '';
        };

        # =====================================================================
        # Package Build
        # =====================================================================
        # Build with: nix build
        #
        # Creates an isolated, reproducible build of caradoc.
        # Output: ./result/bin/caradoc (symlink to nix store)
        #
        # Install to profile: nix profile install .
        # Run directly: nix run . -- stats somefile.pdf
        # =====================================================================
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "caradoc";
          version = "0.3";
          src = ./.;

          nativeBuildInputs = with ocamlPackages; [
            ocaml
            ocamlbuild
            findlib
            menhir
          ] ++ [ pkgs.pkg-config pkgs.m4 pkgs.gnused ];

          buildInputs = with ocamlPackages; [
            cryptokit
            curses
            ounit
          ] ++ [ pkgs.zlib pkgs.gmp pkgs.ncurses ];

          # Patch Makefile for modern OCaml compatibility
          postPatch = makefilePatchCommands;

          buildPhase = ''
            make
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp caradoc $out/bin/
          '';

          meta = with pkgs.lib; {
            description = "A PDF parser and validator written in OCaml";
            homepage = "https://github.com/caradoc-org/caradoc";
            license = licenses.lgpl21Plus;
            platforms = platforms.unix;
            mainProgram = "caradoc";
          };
        };

        # Convenience: allow `nix run` to work
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/caradoc";
        };
      }
    );
}
