{
  ai = null;
  entrypoint = null;
  extraEnv = [
    { name = "AGENT_MODE"; placement = u: u.BuildTime; value = "production"; }
  ];
  mode = u:
    u.InfraAgent;
  name = "my-project-agent";
  nix = {
    buildUserCount = u:
      u.Dynamic;
    enableDaemon = false;
    sandboxPolicy = u:
      u.Auto;
    trustedUsers = [ "root" ];
  };
  packageLayers = [ (u: u.Core) (u: u.Infrastructure) ];
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
