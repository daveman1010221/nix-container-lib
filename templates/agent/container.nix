{
  ai = null;
  entrypoint = null;
  extraEnv = [
    { name = "AGENT_MODE"; placement = u: u.BuildTime; value = "production"; }
  ];
  mode = u:
    u.Agent;
  name = "my-project-agent";
  nix = {
    buildUserCount = u:
      u.Dynamic;
    enableDaemon = false;
    sandboxPolicy = u:
      u.Auto;
    trustedUsers = [ "root" ];
  };
  packageLayers = [
    (u:
      u.Core)
    (u:
      u.Agent)
    (u:
      u.Custom {
        name = "agent-runtime";
        packages = [ { attrPath = "curl"; flakeInput = null; } ];
      })
  ];
  pipeline = null;
  shell = null;
  ssh = null;
  staticGid = null;
  staticUid = null;
  tls = { certsPath = null; enable = true; generateCerts = true; };
  user = {
    createUser = false;
    defaultShell = "/bin/fish";
    skeletonPath = "/etc/container-skel";
    supplementalGroups = [];
  };
}
