#!/usr/bin/env bash

dir="$PWD/`dirname $0`"
source "$dir/setup"
use Test::More
BAIL_ON_FAIL
source "$dir/test-module.sh"

# Default testing values:
{
  test_dir=acme-math-xs-pm
  test_repo_url=$TEST_HOME/../acme-math-xs-pm/.git
  test_prove_run=('prove -lv t/')
  test_test_run=('perl Makefile.PL' 'make test')
  test_make_distdir=('perl Makefile.PL' 'make manifest distdir')
  test_inline_build_dir=.inline
  test_dist=Alt-Acme-Math-XS
  test_dist_files=(
    MANIFEST
    lib/Acme/Math/XS.pm
    inc/Acme/Math/XS/Inline.pm
  )
}

cpp() {
  local test_branch=cpp
  test_module
}

dz() {
  local test_branch=dzil
  local test_test_run=('dzil test')
  local test_make_distdir=('dzil build')
  test_module
}

eumm() {
  local test_branch=eumm
  test_module
}

ext() {
  local test_branch=ext
  test_module
}

m-b() {
  local test_branch='m-b'
  local test_test_run=('perl Build.PL' './Build test')
  local test_make_distdir=('perl Build.PL' './Build manifest' './Build distdir')
  test_module
}

m-i() {
  local test_branch='m-i'
  test_module
}

xs() {
  local test_branch='xs'
  local test_prove_run=('perl Makefile.PL' 'make' 'prove -blv t/')
  local test_inline_build_dir=
  local test_dist=Acme-Math-XS
  test_module
}

zd() {
  local test_branch='zild'
  local test_prove_run=('prove -lv test/')
  local test_test_run=('zild make test')
  local test_make_distdir=('zild make distdir')
  test_module
}

m-p-fs() {
  local test_dir=Math-Prime-FastSieve
  local test_repo_url=$TEST_HOME/../Math-Prime-FastSieve/.git
  local test_dist=Alt-$test_dir
  local test_branch='alt-inline'
  local test_dist_files=(
    MANIFEST
    lib/Math/Prime/FastSieve.pm
    inc/Math/Prime/FastSieve/Inline.pm
  )
  test_module
}

d-g-xs() {
  local test_dir=Devel-GlobalDestruction-XS
  local test_repo_url=$TEST_HOME/../Devel-GlobalDestruction-XS/.git
  local test_dist=Alt-$test_dir
  local test_branch='alt-inline'
  local test_dist_files=(
    MANIFEST
    lib/Devel/GlobalDestruction/XS.pm
    inc/Devel/GlobalDestruction/XS/Inline.pm
  )
  test_module
}

# You can run specific tests like this:
# prove -v test/devel/test-inline-modules.t :: dz cpp d-g-xs
if [ $# -gt 0 ]; then
  for t in "$@"; do
    $t
  done
else
  cpp
  dz
  eumm
  ext
  m-b
  m-i
  xs
  zd
  m-p-fs
  d-g-xs
fi

done_testing;
teardown

# vim: set ft=sh:
