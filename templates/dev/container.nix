{
  ai = null;
  entrypoint = null;
  extraEnv = [
    {
      name = "MY_PROJECT_ENV";
      placement = u:
        u.BuildTime;
      value = "development";
    }
  ];
  mode = u:
    u.Dev;
  name = "my-project-dev";
  nix = {
    buildUserCount = u:
      u.Dynamic;
    enableDaemon = true;
    sandboxPolicy = u:
      u.Auto;
    trustedUsers = [ "root" ];
  };
  packageLayers = [
    (u:
      u.Core)
    (u:
      u.CI)
    (u:
      u.Dev)
    (u:
      u.Toolchain)
    (u:
      u.Pipeline)
  ];
  pipeline = {
    artifactDir = "/workspace/pipeline-out";
    name = "my-project-pipeline";
    outputs = {
      artifacts = [
        {
          artifact = "bin";
          attestation = "build-manifest.json";
          fromStage = "build";
          name = "binaries";
          verifyMethod = "Recompute binding hash from input pins + binary hash";
        }
      ];
      assertions = [
        { fromStage = "fmt"; name = "formatted"; }
        { fromStage = "lint"; name = "lint-clean"; }
        { fromStage = "test-unit"; name = "tests-pass"; }
        { fromStage = "audit"; name = "audit-clean"; }
      ];
    };
    stages = [
      {
        command = "cargo fmt --check";
        condition = null;
        failureMode = u:
          u.Collect;
        impurityReason = null;
        inputs = [ (u: u.Workspace) ];
        name = "fmt";
        outputs = [
          (u:
            u.Assertion {
              description = "Source passes rustfmt";
              name = "formatted";
            })
        ];
        pure = true;
      }
      {
        command = "cargo build --workspace --locked";
        condition = "previous_success";
        failureMode = u:
          u.FailFast;
        impurityReason = null;
        inputs = [ (u: u.Workspace) (u: u.Lockfile) (u: u.Toolchain) ];
        name = "build";
        outputs = [
          (u:
            u.Artifact { "content_type" = "elf-binary-set"; name = "bin"; })
        ];
        pure = true;
      }
    ];
    workingDir = "/workspace/src";
  };
  shell = {
    colorScheme = "gruvbox";
    plugins = [ "bobthefish" "bass" "grc" ];
    shell = "/bin/fish";
    viBindings = true;
  };
  ssh = { enable = false; port = 2223; };
  staticGid = null;
  staticUid = null;
  tls = null;
  user = {
    createUser = true;
    defaultShell = "/bin/fish";
    skeletonPath = "/etc/container-skel";
    supplementalGroups = [];
  };
}
