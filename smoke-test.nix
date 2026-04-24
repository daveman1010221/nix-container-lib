{
  ai = null;
  entrypoint = null;
  extraEnv = [];
  mode = u:
    u.CI;
  name = "polar-container-lib-smoke-test";
  nix = {
    buildUserCount = u:
      u.Dynamic;
    enableDaemon = false;
    sandboxPolicy = u:
      u.Auto;
    trustedUsers = [ "root" ];
  };
  packageLayers = [ (u: u.Micro) (u: u.Core) (u: u.CI) ];
  pipeline = {
    artifactDir = "/workspace/pipeline-out";
    name = "smoke-test-pipeline";
    outputs = null;
    tasks = [
      {
        command = "nu /etc/pipeline/example-build-pipeline.nu";
        condition = null;
        failureMode = u:
          u.Collect;
        impurityReason = null;
        inputs = [ (u: u.Workspace) ];
        name = "build";
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
