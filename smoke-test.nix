{
  ai = null;
  entrypoint = null;
  extraEnv = [];
  mode = u:
    u.Dev;
  name = "polar-container-lib-smoke-test";
  nix = {
    buildUserCount = u:
      u.Dynamic;
    enableDaemon = false;
    sandboxPolicy = u:
      u.Auto;
    trustedUsers = [ "root" ];
  };
  packageLayers = [ (u: u.Micro) (u: u.Core) ];
  pipeline = {
    artifactDir = "/workspace/pipeline-out";
    name = "smoke-test-pipeline";
    outputs = null;
    stages = [
      {
        command = "echo smoke-test-ok";
        condition = null;
        failureMode = u:
          u.Collect;
        impurityReason = null;
        inputs = [ (u: u.Workspace) ];
        name = "check";
        outputs = [ (u: u.None) ];
        pure = true;
      }
    ];
    workingDir = "/workspace";
  };
  shell = null;
  ssh = null;
  staticGid = null;
  staticUid = null;
  tls = null;
  user = {
    createUser = false;
    defaultShell = "/bin/sh";
    skeletonPath = "/etc/container-skel";
    supplementalGroups = [];
  };
}
