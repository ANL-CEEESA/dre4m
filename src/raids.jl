################################################################################
#                    Copyright 2022, UChicago LLC. Argonne                     #
#       This Source Code form is subject to the terms of the MIT license.      #
################################################################################
# vim: tabstop=2 shiftwidth=2 expandtab colorcolumn=80 tw=80

# created @dthierry 2022
# description: module definition for DRE4M
# log:
# 1-30-23 renaming 
#
#
#80#############################################################################
module raids
  include("./matrix/mat_struct.jl")
  include("./gestalt/props.jl")
  include("./gestalt/modKern.jl")
  include("./coef/coef_custom.jl")
  include("./mods/model.jl")
  include("./post/postprocess.jl")
  version = VersionNumber(0, 4, 6)
  @info "RAIDS $(version) by DT@2022"
end
