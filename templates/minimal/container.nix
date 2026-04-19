{
  ai = null;
  entrypoint = null;
  extraEnv = [
    { name = "GIT_TERMINAL_PROMPT"; placement = u: u.BuildTime; value = "0"; }
  ];
  mode = u:
    u.Minimal;
  name = "my-init-container";
  nix = {
    buildUserCount = u:
      u.Dynamic;
    enableDaemon = false;
    sandboxPolicy = u:
      u.Auto;
    trustedUsers = [ "root" ];
  };
  packageLayers = [ (u: u.Micro) ];
  pipeline = null;
  shell = u:
    u.Minimal { shell = "/bin/nu"; };
  ssh = null;
  staticGid = 65532;
  staticUid = 65532;
  tls = null;
  user = {
    createUser = false;
    defaultShell = "/bin/fish";
    skeletonPath = "/etc/container-skel";
    supplementalGroups = [];
  };
}
