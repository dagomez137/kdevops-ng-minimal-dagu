# SPDX-License-Identifier: copyleft-next-0.3.1
#
# Dagu, unmodified, from its release tag.
{
  buildGo127Module,
  fetchFromGitHub,
  fetchPnpmDeps,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  stdenv,
}:
let
  version = "2.20.1";
  src = fetchFromGitHub {
    owner = "dagucloud";
    repo = "dagu";
    tag = "v${version}";
    hash = "sha256-wPgHPDcWhXj/f5Lcgdo9CboCSMVBknMQ4NfBcktuEE8=";
  };
  ui = stdenv.mkDerivation (finalAttrs: {
    pname = "dagu-ui";
    inherit version src;
    sourceRoot = "${finalAttrs.src.name}/ui";
    nativeBuildInputs = [
      nodejs
      pnpm_10
      pnpmConfigHook
    ];
    pnpmDeps = fetchPnpmDeps {
      inherit (finalAttrs)
        pname
        version
        src
        sourceRoot
        ;
      pnpm = pnpm_10;
      fetcherVersion = 4;
      hash = "sha256-SmJUgZcAXlqyS9nRzH+rytScvAHAYTXcy0H6QniB7FU=";
    };
    buildPhase = ''
      runHook preBuild
      NODE_OPTIONS=--max-old-space-size=8192 pnpm exec webpack --config webpack.prod.js
      runHook postBuild
    '';
    installPhase = ''
      cp --recursive dist $out
    '';
  });
in
buildGo127Module {
  pname = "dagu";
  inherit version src;
  vendorHash = "sha256-bPyYjXzMZ0/nCa5i82Q4MK9SCGV/ajkGwY1lMBB5dNk=";
  subPackages = [ "cmd" ];
  ldflags = [ "-X main.version=${version}" ];
  preBuild = ''
    cp ${ui}/* internal/service/frontend/assets/
  '';
  doCheck = false;
  postInstall = ''
    mv $out/bin/cmd $out/bin/dagu
  '';
  meta.mainProgram = "dagu";
}
