{
  ai = null;
  entrypoint = null;
  extraEnv = [];
  mode = u:
    u.CI;
  name = "my-project-ci";
  nix = {
    buildUserCount = u:
      u.Dynamic;
    enableDaemon = false;
    sandboxPolicy = u:
      u.Auto;
    trustedUsers = [ "root" ];
  };
  packageLayers = [ (u: u.Core) (u: u.CI) ];
  pipeline = {
    artifactDir = "/workspace/pipeline-out";
    name = "my-project-pipeline";
    outputs = {
      artifacts = [
        {
          artifact = "bin";
          attestation = "build-manifest.json";
          fromTask = "build";
          name = "binaries";
          verifyMethod = "Recompute binding hash from input pins + binary hash";
        }
      ];
      assertions = [
        { fromTask = "fmt"; name = "formatted"; }
        { fromTask = "lint"; name = "lint-clean"; }
        { fromTask = "test-unit"; name = "tests-pass"; }
        { fromTask = "audit"; name = "audit-clean"; }
      ];
    };
    tasks = [
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
        command = "nu /etc/pipeline/cargo-attested-build.nu --release --artifact-dir /workspace/pipeline-out";
        condition = "previous_success";
        failureMode = u:
          u.FailFast;
        impurityReason = null;
        inputs = [ (u: u.Workspace) (u: u.Lockfile) (u: u.Toolchain) ];
        name = "build";
        outputs = [
          (u:
            u.Artifact { "content_type" = "elf-binary-set"; name = "bin"; })
          (u:
            u.Artifact {
              "content_type" = "attestation-manifest";
              name = "build-manifest.json";
            })
        ];
        pure = true;
      }
    ];
    workingDir = "/workspace/src";
  };
  shell = null;
  ssh = null;
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
