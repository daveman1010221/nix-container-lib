{
  ai = null;
  entrypoint = null;
  extraEnv = [];
  mode = u:
    u.System;
  name = "polar-container-lib-smoke-test-system";
  nix = {
    buildUserCount = u:
      u.Dynamic;
    enableDaemon = false;
    sandboxPolicy = u:
      u.Auto;
    trustedUsers = [ "root" ];
  };
  packageLayers = [ (u: u.Micro) (u: u.Core) ];
  pipeline = null;
  services = [
    {
      after = [];
      command = "/bin/touch /run/marker";
      enabled = true;
      killDelay = null;
      logs = u:
        u.Disabled;
      name = "marker";
      onFailure = u:
        u.Restart;
      onSuccess = u:
        u.Ignore;
      summary = "a one-shot: leaves /run/marker";
    }
    {
      after = [ "marker" ];
      command = "/bin/sleep 100000";
      enabled = true;
      killDelay = "2s";
      logs = u:
        u.Enabled;
      name = "ticker";
      onFailure = u:
        u.Restart;
      onSuccess = u:
        u.Restart;
      summary = "a daemon, started once marker runs";
    }
  ];
  shell = null;
  ssh = null;
  startup = {
    boot = [
      (u:
        u.DelegateCgroups)
      (u:
        u.Script {
          command = "/bin/touch /run/booted";
          name = "booted";
          required = true;
        })
    ];
    launch = u:
      u.System;
    session = u:
      u.None;
  };
  staticGid = null;
  staticUid = null;
  tls = null;
  user = {
    createUser = false;
    defaultShell = "/bin/fish";
    skeletonPath = "/etc/container-skel";
    supplementalGroups = [];
  };
}
