# SPDX-License-Identifier: copyleft-next-0.3.1
#
# The host's xfstests share, where xfstests@<section>.service reads each
# section's config and environment and writes its results.
{
  nixos-flake.shares."/var/lib/xfstests".tag = "xfstests";
}
