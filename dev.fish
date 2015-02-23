# source this to create a lit-def function that runs directly our of this dir in dev mode.
set lit_dir (pwd)
set lit_bin (pwd)/lit

function lit-dev
  set -x LUVI_APP $lit_dir
  eval $lit_bin $argv
  set -e LUVI_APP
end
