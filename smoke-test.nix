{
  extraEnv = [];
  mode = u:
    u.CI;
  name = "polar-container-lib-smoke-test";
  nix = {
    buildUserCount = u:
      u.Dynamic;
    enableDaemon = true;
    sandboxPolicy = u:
      u.Auto;
    trustedUsers = [ "root" ];
  };
  packageLayers = [ (u: u.Core) (u: u.CI) ];
  pipeline = null;
  shell = null;
  ssh = null;
  tls = null;
  user = {
    createUser = false;
    defaultShell = "/bin/fish";
    skeletonPath = "/etc/container-skel";
  };
}
