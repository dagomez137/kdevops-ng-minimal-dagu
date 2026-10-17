# SPDX-License-Identifier: copyleft-next-0.3.1
#
# dbench, the filesystem load generator xfstests' generic/241 runs.
#
# The test calls `dbench -t 60 -D <dir> 4`, the interface dbench 4.0 has:
# fileio backend and the bundled client.txt load file by default. Upstream
# made both mandatory arguments in October 2013, and nixpkgs dropped the
# package in 2025, so this builds the last revision before that change.
# The binary reads DATADIR/client.txt, which `make install` does not put
# there.
#
# Source: https://github.com/sahlberg/dbench
{
  lib,
  stdenv,
  fetchFromGitHub,
  autoconf,
  popt,
  zlib,
}:

stdenv.mkDerivation {
  pname = "dbench";
  version = "4.0-unstable-2013-10-26";

  src = fetchFromGitHub {
    owner = "sahlberg";
    repo = "dbench";
    rev = "caa52d347171f96eef5f8c2d6ab04a9152eaf113";
    hash = "sha256-fuByesg14VwxPf01iL6Xx0W/PMyO+n/Xr1fKP/NiRUA=";
  };

  # gzopen() returns a gzFile, which is already a pointer; GCC 14 makes
  # the gzFile * declarations an error.
  patches = [ ./dbench-gzfile.patch ];

  nativeBuildInputs = [ autoconf ];
  buildInputs = [
    popt
    zlib
  ];

  preConfigure = "./autogen.sh";

  postInstall = ''
    install -D --mode=0644 loadfiles/client.txt $out/share/client.txt
  '';

  meta = {
    description = "Filesystem benchmark that generates the I/O load of a file server";
    homepage = "https://github.com/sahlberg/dbench";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "dbench";
  };
}
