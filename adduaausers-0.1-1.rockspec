package = "adduaausers"
version = "0.1-1"
source = {
   url = "*** please add URL for source tarball, zip or repository here ***"
}
description = {
   homepage = "*** please enter a project homepage ***",
   license = "*** please specify a license ***"
}
dependencies = {
   "yaml 1.1.2-1"
}
build = {
   type = "builtin",
   modules = {
      adduaausers = "adduaausers.lua"
   }
}
