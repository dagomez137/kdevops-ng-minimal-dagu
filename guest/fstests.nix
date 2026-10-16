# SPDX-License-Identifier: copyleft-next-0.3.1
#
# Run fstests once at boot, then power off. The host lays the configuration
# down on the xfstests share before boot and reads the results and the unit's
# outcome back from it after the guest has stopped.
{ pkgs, ... }:
let
  dir = "/var/lib/xfstests";
in
{
  nixos-flake.shares.${dir}.tag = "xfstests";

  systemd.services.fstests = {
    description = "fstests, then power off";
    wantedBy = [ "multi-user.target" ];
    # check and the tests run the fstests userland by bare name.
    path = [ "/run/current-system/sw" ];
    environment.HOST_OPTIONS = "${dir}/fstests.config";
    unitConfig = {
      RequiresMountsFor = dir;
      SuccessAction = "poweroff";
      FailureAction = "poweroff";
    };
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "${dir}/fstests.config";
      ExecStartPre = [
        "${pkgs.systemd}/bin/udevadm wait --timeout=60 $TEST_DEV $SCRATCH_DEV"
        "${pkgs.xfsprogs}/bin/mkfs.xfs -f $TEST_DEV"
        "${pkgs.coreutils}/bin/mkdir --parents $TEST_DIR $SCRATCH_MNT"
      ];
      ExecStart = "${pkgs.xfstests}/bin/xfstests-check $FSTESTS_ARGS";
      ExecStopPost = pkgs.writeShellScript "fstests-status" ''
        echo "$SERVICE_RESULT $EXIT_STATUS" > ${dir}/status
      '';
      StandardOutput = "journal+console";
      StandardError = "journal+console";
      TimeoutStartSec = "infinity";
      # Tests stop pipeline helpers with SIGPIPE.
      IgnoreSIGPIPE = false;
    };
  };
}
