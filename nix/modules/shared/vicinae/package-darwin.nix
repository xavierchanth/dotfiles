{
  fetchurl,
  lib,
  stdenvNoCC,
  _7zz,
}:
stdenvNoCC.mkDerivation {
  pname = "vicinae-bin";
  version = "0.28.2";

  src = fetchurl {
    url = "https://github.com/vicinaehq/vicinae/releases/download/v0.28.2/Vicinae.dmg";
    hash = "sha256-AF40jc4D9Qq2vGpNjgXQn8wCFqhGtgfbwC5KkWj6eqk=";
  };

  nativeBuildInputs = [_7zz];
  sourceRoot = ".";
  unpackPhase = ''
    7zz x -aoa -snld "$src"
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    cp -R Vicinae.app "$out/Applications/Vicinae.app"
    ln -s ../Applications/Vicinae.app/Contents/MacOS/vicinae-cli "$out/bin/vicinae"
    runHook postInstall
  '';

  meta = {
    description = "A focused launcher for your desktop";
    homepage = "https://vicinae.com";
    license = lib.licenses.gpl3Plus;
    mainProgram = "vicinae";
    platforms = ["aarch64-darwin"];
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
  };
}
