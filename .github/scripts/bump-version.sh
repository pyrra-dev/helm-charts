#!/bin/bash
# ugly-ass script to bump versions in Chart.yaml
# assign vars from args
chart=${1}
patchlevel=${2}

# exit on no args
if [[ ${1} == "" && ${2} == "" ]];
  then
  echo "Usage: update-helper.sh chart_name patchlevel"
  echo "patchlevel can be either major, minor or patch"
  exit 0
fi

# ugly symlink so it works on both linux and OSX
sedlink() {
  if [[ "${OSTYPE}" == "linux-gnu"* ]]; then
    sed "$@"
  elif [[ "${OSTYPE}" == "darwin"* ]]; then
    gsed "$@"
  else
    sed "$@"
  fi
}

# function to work with semver, source:
# https://github.com/fmahnke/shell-semver/blob/master/increment_version.sh
semver_increment() {
  case ${patchlevel} in
    major ) major=true;;
    minor ) minor=true;;
    patch ) patch=true;;
  esac

  shift $(($OPTIND - 1))

  version=$(grep "version:" charts/${chart}/Chart.yaml | awk {'print $2'})

  # Build array from version string.

  a=( ${version//./ } )

  # Increment version numbers as requested.

  if [ ! -z $major ]
  then
    ((a[0]++))
    a[1]=0
    a[2]=0
  fi

  if [ ! -z $minor ]
  then
    ((a[1]++))
    a[2]=0
  fi

  if [ ! -z $patch ]
  then
    ((a[2]++))
  fi

  echo "${a[0]}.${a[1]}.${a[2]}"
}

#set to version we need
target_version=$(semver_increment ${current_version} ${patchlevel})
#patch it around
sedlink -i "s/^version:.*$/version: ${target_version}/g" charts/${chart}/Chart.yaml
#extract image version from values (multiple different images not supported)
appversion=$(grep "tag:" charts/${chart}/values.yaml | awk {'print $2'} | tr -d '"')
#patch it around
sedlink -i "s/^appVersion:.*$/appVersion: ${appversion}/g" charts/${chart}/Chart.yaml