{ lib
, fetchurl
, kaem
, tinycc
, gnupatch
}:
let
  pname = "gnumake";
  version = "4.4.1";

  src = fetchurl {
    url = "mirror://gnu/make/make-${version}.tar.gz";
    sha256 = "1cwgcmwdn7gqn5da2ia91gkyiqs9birr10sy5ykpkaxzcwfzn5nx";
  };

  patches = [
    # Replaces /bin/sh with sh, see patch file for reasoning
    ./0001-No-impure-bin-sh.patch
    # Purity: don't look for library dependencies (of the form `-lfoo') in /lib
    # and /usr/lib. It's a stupid feature anyway. Likewise, when searching for
    # included Makefiles, don't look in /usr/include and friends.
    ./0002-remove-impure-dirs.patch
    # Fixes for tinycc. See comments in patch file for reasoning
    ./0003-tinycc-support.patch
  ];

  CFLAGS = [
    "-I./src"
    "-I./lib"
    "-DHAVE_CONFIG_H"
    "-DMAKE_MAINTAINER_MODE"
    "-DLIBDIR=\\\"${placeholder "out"}/lib\\\""
    "-DLOCALEDIR=\\\"/fake-locale\\\""
    "-DPOSIX=1"
    # mes-libc doesn't implement osync_* methods
    "-DNO_OUTPUT_SYNC=1"
    # mes-libc doesn't define O_TMPFILE
    "-DO_TMPFILE=020000000"
  ] ++ config;

  /*
    Maintenance notes:

    Generated by
        ./configure \
          --build i686-pc-linux-gnu \
          --host i686-pc-linux-gnu \
          CC="${tinycc.compiler}/bin/tcc -B ${tinycc.libs}/lib -static" \
          ac_cv_func_dup=no
    - `ac_cv_func_dup` disabled as mes-libc doesn't implement tmpfile()

    The output src/config.h was then manually filtered, removing definitions that
    didn't have uses in the source code
  */
  config = [
    "-DFILE_TIMESTAMP_HI_RES=0"
    "-DHAVE_ALLOCA"
    "-DHAVE_ALLOCA_H"
    "-DHAVE_ATEXIT"
    "-DHAVE_DECL_BSD_SIGNAL=0"
    "-DHAVE_DECL_GETLOADAVG=0"
    "-DHAVE_DECL_SYS_SIGLIST=0"
    "-DHAVE_DECL__SYS_SIGLIST=0"
    "-DHAVE_DECL___SYS_SIGLIST=0"
    "-DHAVE_DIRENT_H"
    "-DHAVE_DUP2"
    "-DHAVE_FCNTL_H"
    "-DHAVE_FDOPEN"
    "-DHAVE_GETCWD"
    "-DHAVE_GETTIMEOFDAY"
    "-DHAVE_INTTYPES_H"
    "-DHAVE_ISATTY"
    "-DHAVE_LIMITS_H"
    "-DHAVE_LOCALE_H"
    "-DHAVE_MEMORY_H"
    "-DHAVE_MKTEMP"
    "-DHAVE_SA_RESTART"
    "-DHAVE_SETVBUF"
    "-DHAVE_SIGACTION"
    "-DHAVE_SIGSETMASK"
    "-DHAVE_STDINT_H"
    "-DHAVE_STDLIB_H"
    "-DHAVE_STRDUP"
    "-DHAVE_STRERROR"
    "-DHAVE_STRINGS_H"
    "-DHAVE_STRING_H"
    "-DHAVE_STRTOLL"
    "-DHAVE_SYS_FILE_H"
    "-DHAVE_SYS_PARAM_H"
    "-DHAVE_SYS_RESOURCE_H"
    "-DHAVE_SYS_SELECT_H"
    "-DHAVE_SYS_STAT_H"
    "-DHAVE_SYS_TIMEB_H"
    "-DHAVE_SYS_TIME_H"
    "-DHAVE_SYS_WAIT_H"
    "-DHAVE_TTYNAME"
    "-DHAVE_UMASK"
    "-DHAVE_UNISTD_H"
    "-DHAVE_WAITPID"
    "-DMAKE_JOBSERVER"
    "-DMAKE_SYMLINKS"
    "-DPATH_SEPARATOR_CHAR=':'"
    "-DSCCS_GET=\\\"get\\\""
    "-DSTDC_HEADERS"
    "-Dsig_atomic_t=int"
    "-Dvfork=fork"
  ];

  # Maintenance note: list of source files derived from Basic.mk
  make_SOURCES = [
    "src/ar.c"
    "src/arscan.c"
    "src/commands.c"
    "src/default.c"
    "src/dir.c"
    "src/expand.c"
    "src/file.c"
    "src/function.c"
    "src/getopt.c"
    "src/getopt1.c"
    "src/guile.c"
    "src/hash.c"
    "src/implicit.c"
    "src/job.c"
    "src/load.c"
    "src/loadapi.c"
    "src/main.c"
    "src/misc.c"
    "src/output.c"
    "src/read.c"
    "src/remake.c"
    "src/rule.c"
    "src/shuffle.c"
    "src/signame.c"
    "src/strcache.c"
    "src/variable.c"
    "src/version.c"
    "src/vpath.c"
  ];
  glob_SOURCES = [ "lib/fnmatch.c" "lib/glob.c" ];
  remote_SOURCES = [ "src/remote-stub.c" ];
  sources = make_SOURCES ++ glob_SOURCES ++ remote_SOURCES ++ [
    "src/posixos.c"
  ];

  objects = map (x: lib.replaceStrings [".c"] [".o"] (builtins.baseNameOf x)) sources;
in
kaem.runCommand "${pname}-${version}" {
  inherit pname version;

  nativeBuildInputs = [ tinycc.compiler gnupatch ];

  meta = with lib; {
    description = "A tool to control the generation of non-source files from sources";
    homepage = "https://www.gnu.org/software/make";
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [ emilytrau ];
    mainProgram = "make";
    platforms = platforms.unix;
  };
} ''
  # Unpack
  ungz --file ${src} --output make.tar
  untar --file make.tar
  rm make.tar
  cd make-${version}

  # Patch
  ${lib.concatMapStringsSep "\n" (f: "patch -Np1 -i ${f}") patches}

  # Configure
  catm src/config.h src/mkconfig.h src/mkcustom.h
  cp lib/glob.in.h lib/glob.h
  cp lib/fnmatch.in.h lib/fnmatch.h

  # Compile
  alias CC="tcc -B ${tinycc.libs}/lib ${lib.concatStringsSep " " CFLAGS}"
  ${lib.concatMapStringsSep "\n" (f: "CC -c ${f}") sources}

  # Link
  CC -static -o make ${lib.concatStringsSep " " objects}

  # Check
  ./make --version

  # Install
  mkdir -p ''${out}/bin
  cp ./make ''${out}/bin
  chmod 555 ''${out}/bin/make
''
