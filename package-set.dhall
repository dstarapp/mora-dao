let upstream = https://github.com/dfinity/vessel-package-set/releases/download/mo-0.10.4-20240112/package-set.dhall
let Package = { name : Text, version : Text, repo : Text, dependencies : List Text }
let additions = [
  { name = "base"
  , repo = "https://github.com/dfinity/motoko-base"
  , version = "moc-0.11.1"
  , dependencies = [] : List Text
  },
  { name = "io"
  , repo = "https://github.com/aviate-labs/io.mo"
  , version = "v0.3.0"
  , dependencies = [ "base" ]
  },
  { name = "array"
  , repo = "https://github.com/aviate-labs/array.mo"
  , version = "v0.2.0"
  , dependencies = [ "base" ]
  },
  { name = "encoding"
  , repo = "https://github.com/aviate-labs/encoding.mo"
  , version = "v0.3.2"
  , dependencies = [ "array", "base" ]
  },
  { name = "hash"
  , repo = "https://github.com/aviate-labs/hash.mo"
  , version = "v0.1.0"
  , dependencies = [ "base", "array" ]
  },
  { name = "mutable-queue"
  , repo = "https://github.com/ninegua/mutable-queue.mo"
  , version = "2759a3b8d61acba560cb3791bc0ee730a6ea8485"
  , dependencies = [ "base" ]
  },
  { name = "crypto"
  , repo = "https://github.com/aviate-labs/crypto.mo"
  , version = "v0.2.0"
  , dependencies = [ "base", "encoding" ]
  },
  { name = "principal"
  , repo = "https://github.com/aviate-labs/principal.mo"
  , version = "v0.2.5"
  , dependencies = [ "base", "array", "crypto", "hash" ]
  },
] : List Package
in  upstream # additions
