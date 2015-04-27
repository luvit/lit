# source this to create a lit-def function that runs directly our of this dir in dev mode.
set lit_dir (pwd)
set luvi_bin (pwd)/luvi

function lit-dev
  eval $luvi_bin $lit_dir -- $argv
end
