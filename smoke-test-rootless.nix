{
  agentPassEnvGlob = [ "*" ];
  ai = null;
  entrypoint = null;
  extraEnv = [];
  mode = u:
    u.Dev;
  name = "polar-container-lib-smoke-test-rootless";
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
      u.Core)
    (u:
      u.Custom {
        name = "ssh";
        packages = [ { attrPath = "dropbear"; flakeInput = null; } ];
      })
  ];
  pipeline = null;
  services = [];
  shell = u:
    u.Interactive {
      colorScheme = "gruvbox";
      plugins = [ "bobthefish" "bass" "grc" ];
      shell = "/bin/fish";
      viBindings = true;
    };
  ssh = { enable = false; port = 2223; };
  startup = {
    boot = [];
    launch = u:
      u.Headless;
    session = u:
      u.Rootless { gid = 1000; name = "dev"; uid = 1000; };
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
