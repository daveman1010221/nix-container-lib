# The first line of a fish function that needs commands of its image's: they are looked for when it is called, never
# while the image is evaluated. Asking at evaluation whether `${devEnv}/bin/<name>` exists built the whole environment
# before the image could be evaluated, so a builder with no way out could not evaluate it. A command missing is named, and
# the function returns 127, as fish does for a command not found.
fn: commands:
"for __needed in ${builtins.concatStringsSep " " commands}; command -q $__needed; or begin; echo \"${fn}: $__needed is not in this container\" >&2; return 127; end; end"
