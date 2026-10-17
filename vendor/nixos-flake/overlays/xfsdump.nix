# SPDX-License-Identifier: copyleft-next-0.3.1
#
# xfsdump strcpy()s each directory entry name into the fixed-size dh_name
# stub of its record header, which _FORTIFY_SOURCE=3 (nixpkgs' default)
# turns into an abort on the first long name. Copy past the stub instead.
final: prev: {
  xfsdump = prev.xfsdump.overrideAttrs (prevAttrs: {
    patches = (prevAttrs.patches or [ ]) ++ [ ./xfsdump-dirent-name-fortify.patch ];
  });
}
