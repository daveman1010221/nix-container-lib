{
  ai = null;
  entrypoint = "my-entrypoint-binary";
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
  packageLayers = [
    (u:
      u.Micro)
    (u:
      u.Custom {
        name = "my-entrypoint";
        packages = [
          { attrPath = "packages.default"; flakeInput = "myInput"; }
        ];
      })
  ];
  pipeline = null;
  shell = null;
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
