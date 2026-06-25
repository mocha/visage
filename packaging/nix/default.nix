# Visage — NixOS package derivation
#
# Usage (standalone):
#   nix build .#visage
#
# Usage (NixOS module — recommended):
#   imports = [ visage.nixosModules.default ];
#   services.visage.enable = true;
#
# For nixpkgs submission, replace src/cargoLock with fetchFromGitHub + cargoHash.

{ lib
, rustPlatform
, pkg-config
, pam
, dbus
, onnxruntime
, makeWrapper
, substituteAll ? null
}:

rustPlatform.buildRustPackage {
  pname = "visage";
  version = "0.3.3";

  src = lib.cleanSource ../..;

  cargoLock.lockFile = ../../Cargo.lock;

  # bindgenHook: v4l2-sys-mit runs bindgen at build time, which needs libclang
  # (sets LIBCLANG_PATH). pkg-config locates pam/dbus.
  nativeBuildInputs = [ pkg-config rustPlatform.bindgenHook makeWrapper ];
  buildInputs = [ pam dbus ];

  # cargo test runs unit tests; integration tests require a camera + daemon.
  # ORT_DYLIB_PATH: with ort load-dynamic, any test that constructs a Session
  # dlopen()s the runtime at test time, so point it at nixpkgs onnxruntime.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    export ORT_DYLIB_PATH=${onnxruntime}/lib/libonnxruntime.so
    cargo test --workspace --lib
    runHook postCheck
  '';

  postInstall = ''
    # PAM module (cdylib — not installed by cargo install). Recent buildRustPackage
    # builds under a target-triple subdir (target/<triple>/release), not target/release.
    install -Dm755 target/*/release/libpam_visage.so \
      $out/lib/security/pam_visage.so

    # ort load-dynamic: visaged dlopen()s onnxruntime via ORT_DYLIB_PATH at runtime.
    wrapProgram $out/bin/visaged \
      --set ORT_DYLIB_PATH ${onnxruntime}/lib/libonnxruntime.so

    # D-Bus system bus policy
    install -Dm644 packaging/dbus/org.freedesktop.Visage1.conf \
      $out/share/dbus-1/system.d/org.freedesktop.Visage1.conf

    # systemd units — patch ExecStart to reference the Nix store path
    install -Dm644 packaging/systemd/visaged.service \
      $out/lib/systemd/system/visaged.service
    substituteInPlace $out/lib/systemd/system/visaged.service \
      --replace-fail "/usr/bin/visaged" "$out/bin/visaged"

    install -Dm644 packaging/systemd/visage-resume.service \
      $out/lib/systemd/system/visage-resume.service
    substituteInPlace $out/lib/systemd/system/visage-resume.service \
      --replace-fail "/usr/bin/systemctl" "systemctl"
  '';

  meta = with lib; {
    description = "Linux face authentication via PAM — persistent daemon, IR camera support, ONNX inference";
    longDescription = ''
      Visage is the Windows Hello equivalent for Linux. It authenticates sudo,
      login, and any PAM-gated service using your face — with sub-second response
      and no subprocess overhead. Built in Rust with a persistent daemon model,
      SCRFD face detection, and ArcFace recognition via ONNX Runtime.

      The default face authentication layer for Augmentum OS.
      Ships standalone on any Linux system.
    '';
    homepage = "https://github.com/sovren-software/visage";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
    mainProgram = "visage";
  };
}
