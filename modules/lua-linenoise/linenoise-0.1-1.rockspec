package = 'linenoise'
version = '0.1-1'
source = {
  url = 'https://github.com/downloads/hoelzro/lua-linenoise/lua-linenoise-0.1.tar.gz'
}
description = {
  summary  = 'A binding for the linenoise command line library',
  homepage = 'https://github.com/hoelzro/lua-linenoise',
  license  = 'MIT/X11',
}
dependencies = {
  'lua >= 5.1'
}

build = {
  type    = 'builtin',
  modules = {
    linenoise = {
      sources   = { 'linenoise.c' },
      libraries = { 'linenoise' },
    },
  },
}
