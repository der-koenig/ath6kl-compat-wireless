#!/bin/bash
# Copyright 2009  Luis R. Rodriguez <mcgrof@gmail.com>
#
# You can use this to make stable compat-wireless releases
#
# The assumption is you have the linux-2.6-allstable git tree on your $HOME
# git://git.kernel.org/pub/scm/linux/kernel/git/hpa/linux-2.6-allstable.git
#
# Local branches will be created based on the remote linux-2.6.X.y branches.
# If your branch already exists we will nuke it for you to avoid rebasing.
#
# If no kernel is specified we use the latest rc-release, which will be on the
# remove master branch. Your master branch should be clean.

ALL_STABLE_TREE="linux-2.6-allstable"
STAGING=/tmp/staging/compat-wireless/

function usage()
{
	echo "Usage: $1 <linux-2.6.X.y>"
	echo
	echo Examples usages:
	echo
	echo  $1
	echo  $1 linux-2.6.29.y
	echo  $1 linux-2.6.30.y
	echo
	echo "If no kernel is specified we try to make a release based on the latest RC kernel."
	echo "If a kernel release is specified X is the next stable release as 35 in 2.6.35.y."
	exit
}

UPDATE_ARGS=""
# branch we want to use from hpa's tree, by default
# this is origin/master as this will get us the latest
# RC kernel.
LOCAL_BRANCH="master"
POSTFIX_RELEASE_TAG="-"

# By default we will not do a git fetch and reset of the branch,
# use -f if you want to force an update, this will delete all
# of your local patches so be careful.
FORCE_UPDATE="no"

while [ $# -ne 0 ]; do
	if [[ "$1" = "-n" ]]; then
		UPDATE_ARGS="${UPDATE_ARGS} $1"
		POSTFIX_RELEASE_TAG="${POSTFIX_RELEASE_TAG}n"
		shift; continue;
	fi
	if [[ "$1" = "-p" ]]; then
		UPDATE_ARGS="${UPDATE_ARGS} $1"
		POSTFIX_RELEASE_TAG="${POSTFIX_RELEASE_TAG}p"
		shift; continue;
	fi
	if [[ "$1" = "-c" ]]; then
		UPDATE_ARGS="${UPDATE_ARGS} $1"
		POSTFIX_RELEASE_TAG="${POSTFIX_RELEASE_TAG}c"
		shift; continue;
	fi
	if [[ "$1" = "-f" ]]; then
		FORCE_UPDATE="yes"
		shift; continue;
	fi

	if [[ $(expr "$1" : '^linux-') -eq 6 ]]; then
		LOCAL_BRANCH="$1"
		shift; continue;
	fi

	echo "Unexpected argument passed: $1"
	usage $0
	exit
done

export GIT_TREE=$HOME/$ALL_STABLE_TREE
COMPAT_WIRELESS_DIR=$(pwd)
COMPAT_WIRELESS_BRANCH=$(git branch | grep \* | awk '{print $2}')

cd $GIT_TREE
# --abbrev=0 on branch should work but I guess it doesn't on some releases
EXISTING_BRANCH=$(git branch | grep \* | awk '{print $2}')
# This is a super hack, but let me know if you figure out a cleaner way
TARGET_KERNEL_RELEASE=$(make VERSION="linux-2" EXTRAVERSION=".y" kernelversion)

if [[ $COMPAT_WIRELESS_BRANCH != $TARGET_KERNEL_RELEASE ]]; then
	echo "You are not on the branch $COMPAT_WIRELESS_BRANCH on compat-wireless,"
	echo "try changing to that first."
	exit
fi

case $LOCAL_BRANCH in
"master") # Preparing a new stable compat-wireless release based on an RC kernel
	if [[ $FORCE_UPDATE = "yes" || "$EXISTING_BRANCH" != "$LOCAL_BRANCH" ]]; then
		git checkout -f
		git fetch
		git reset --hard origin
	fi
	echo "On master branch on $ALL_STABLE_TREE"
	;;
*) # Based on a stable 2.6.x.y release, lets just move to the master branch,
   # git pull, nuke the old branch and start a fresh new branch.
	if [[ $FORCE_UPDATE = "yes" || "$EXISTING_BRANCH" != "$LOCAL_BRANCH" ]]; then
		git checkout -f
		git fetch
		if [[ "$EXISTING_BRANCH" = "$LOCAL_BRANCH" ]]; then
			git branch -m crap-foo-compat
		fi
		git branch -D $LOCAL_BRANCH
		git checkout -b $LOCAL_BRANCH origin/$LOCAL_BRANCH
		if [[ "$EXISTING_BRANCH" -eq "$LOCAL_BRANCH" ]]; then
			git branch -D crap-foo-compat
		fi
	fi
	echo "On non-master branch on $ALL_STABLE_TREE: $LOCAL_BRANCH"
	;;
esac

# We should now be on the branch we want
KERNEL_RELEASE=$(git describe --abbrev=0 | sed -e 's/v//g')
RELEASE="compat-wireless-$KERNEL_RELEASE"
if [[ $POSTFIX_RELEASE_TAG != "-" ]]; then
	RELEASE="${RELEASE}${POSTFIX_RELEASE_TAG}"
fi
RELEASE_TAR="$RELEASE.tar.bz2"

rm -rf $STAGING
mkdir -p $STAGING
cp -a $COMPAT_WIRELESS_DIR $STAGING/$RELEASE
cd $STAGING/$RELEASE

./scripts/admin-update.sh $UPDATE_ARGS
rm -rf $STAGING/$RELEASE/.git

# Remove any gunk
echo
echo "Cleaning up the release ..."
make clean 2>&1 > /dev/null
find ./ -type f -name *.orig | xargs rm -f
find ./ -type f -name *.rej  | xargs rm -f

cd $STAGING/

echo "Creating $RELEASE_TAR ..."
tar -jcf $RELEASE_TAR $RELEASE/

echo
echo "Compat-wireles release: $RELEASE"
echo "Size: $(du -h $RELEASE_TAR)"
echo "sha1sum: $(sha1sum $RELEASE_TAR)"
echo
echo "Release: ${STAGING}$RELEASE_TAR"
