{
  ai = { enable = false; llamaPort = 8080; modelsPath = "/opt/llama-models"; };
  entrypoint = null;
  extraEnv = [
    { name = "AGENT_MODE"; placement = u: u.BuildTime; value = "production"; }
  ];
  mode = u:
    u.AIAgent;
  name = "my-project-agent";
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
  shell = u:
    u.Minimal { shell = "/bin/nu"; };
  ssh = { enable = false; port = 2223; };
  staticGid = null;
  staticUid = null;
  tls = { certsPath = null; enable = true; generateCerts = true; };
  user = {
    createUser = true;
    defaultShell = "/bin/fish";
    skeletonPath = "/etc/container-skel";
    supplementalGroups = [];
  };
}
