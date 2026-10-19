# SPDX-License-Identifier: copyleft-next-0.3.1
#
# The host's share for each test suite, where its units read their
# configuration and write their results: xfstests@<section>.service,
# kselftest@<collection>.service and usertests@<program>.service.
{
  nixos-flake.shares."/var/lib/xfstests".tag = "xfstests";
  nixos-flake.shares."/var/lib/kselftests".tag = "selftests";
  nixos-flake.shares."/var/lib/usertests".tag = "usertests";
}
