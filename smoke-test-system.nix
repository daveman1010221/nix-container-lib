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
      environment = [];
      killDelay = null;
      logs = u:
        u.Disabled;
      name = "marker";
      onFailure = u:
        u.Restart;
      onSuccess = u:
        u.Ignore;
      passEnv = false;
      passEnvGlob = [];
      passEnvRegex = [];
      summary = "a one-shot: leaves /run/marker";
    }
    {
      after = [ "marker" ];
      command = "/bin/sleep 100000";
      enabled = true;
      environment = [];
      killDelay = "2s";
      logs = u:
        u.Enabled;
      name = "ticker";
      onFailure = u:
        u.Restart;
      onSuccess = u:
        u.Restart;
      passEnv = false;
      passEnvGlob = [];
      passEnvRegex = [];
      summary = "a daemon, started once marker runs";
    }
    {
      after = [];
      command = "/bin/env";
      enabled = true;
      environment = [ { mapKey = "PROBE_SET"; mapValue = "yes"; } ];
      killDelay = null;
      logs = u:
        u.Enabled;
      name = "env-probe";
      onFailure = u:
        u.Restart;
      onSuccess = u:
        u.Ignore;
      passEnv = false;
      passEnvGlob = [ "PROBE_*" ];
      passEnvRegex = [];
      summary = "prints the environment it gets";
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
