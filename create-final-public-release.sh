#!/usr/bin/env bash
# set -o pipefail  # exit if pipe command fails
[ -z "$DEBUG" ] || set -x
set -e

##

RELEASE="oauth2-proxy"
DESCRIPTION="Oauth2-proxy Bosh Release"
GITHUB_REPO="SpringerPE/oauth2-proxy-boshrelease"
# Do not define this variable if the repo uses git lfs
# https://starkandwayne.com/blog/bosh-releases-with-git-lfs/
RELEASE_BUCKET="oauth2-proxy-boshrelease"

###

BOSH_CLI=${BOSH_CLI:-bosh}
S3CMD=${S3CMD:-s3cmd}
JQ=jq
CURL="curl -s"
SHA1="sha1sum -b"
RE_VERSION_NUMBER='^[0-9]+([0-9\.]*[0-9]+)*$'

# Create a personal github token to use this script
if [ -z "$GITHUB_TOKEN" ]
then
    echo "Github TOKEN not defined!"
    echo "See https://help.github.com/articles/creating-an-access-token-for-command-line-use/"
    exit 1
fi

# You need bosh installed and with you credentials
if ! [ -x "$(command -v $BOSH_CLI)" ]
then
    echo "ERROR: $BOSH_CLI command not found! Please install it and make it available in the PATH"
    exit 1
fi

# You need jq installed
if ! [ -x "$(command -v $JQ)" ]
then
    echo "ERROR: $JQ command not found! Please install it and make it available in the PATH"
    exit 1
fi

# You need sha1sum installed  (brew md5sha1sum)
if ! [ -x "$(command -v $SHA1)" ]
then
    echo "ERROR: $SHA1 command not found! Please install it and make it available in the PATH"
    exit 1
fi

if [ -n "$RELEASE_BUCKET" ]
then
    # You need s3cmd installed and with you credentials
    if ! [ -x "$(command -v $S3CMD)" ]
    then
        echo "$S3CMD command not found!"
        exit 1
    fi
    # Checking if the bucket is there. If not, create it first (this just a check to
    # be sure that s3cmd is properly setup and with the correct credentials
    if ! $S3CMD ls | grep -q "s3://$RELEASE_BUCKET"
    then
        echo "Bucket 's3://$RELEASE_BUCKET' not found! Please create it first!"
        exit 1
    fi
fi

case $# in
    0)
        echo "*** Creating a new release. Automatically calculating next release version number"
        ;;
    1)
        if [ $1 == "-h" ] || [ $1 == "--help" ]
        then
            echo "Usage:  $0 [version-number]"
            echo "  Creates a new boshrelease, commits the changes to this repository using tags and uploads "
            echo "  the release to Github releases. It also adds comments based on previous git commits and "
            echo "  calculates the sha1 checksum."
            exit 0
        else
            version=$1
            if ! [[ $version =~ $RE_VERSION_NUMBER ]]
            then
                echo "ERROR: Incorrect version number!"
                exit 1
            fi
            echo "*** Creating a new release. Using release version number $version."
        fi
        ;;
    *)
        echo "ERROR: incorrect argument. See '$0 --help'"
        exit 1
        ;;
esac


# Get the last git commit made by this script
lastcommit=$(git log --format="%h" --grep="$RELEASE v*" | head -1)
echo "* Changes since last version with commit $lastcommit: "
git_changes=$(git log --pretty="%h %aI %s (%an)" $lastcommit..@ | sed 's/^/- /')
if [ -z "$git_changes" ]
then
    echo "Error, no commits since last release with commit $lastcommit!. Please "
    echo "commit your changes to create and publish a new release!"
    exit 1
fi
echo "$git_changes"

# Uploading blobs
echo "* Uploading blobs to the blobstore ..."
$BOSH_CLI upload-blobs

# Creating the release
if [ -z "$version" ]
then
    echo "* Creating final release ..."
    $BOSH_CLI create-release --force --final --tarball="/tmp/$RELEASE-$$.tgz" --name "$RELEASE"
    # Get the version of the release
    version=$(ls releases/$RELEASE/$RELEASE-*.yml | sed 's/.*\/.*-\(.*\)\.yml$/\1/' | sort -rn | head -1)
else
    echo "* Creating final release version $version ..."
    $BOSH_CLI create-release --force --final --tarball="/tmp/$RELEASE-$$.tgz" --name "$RELEASE" --version "$version"
fi

# Create a release in Github
sha1=$($SHA1 "/tmp/$RELEASE-$$.tgz" | cut -d' ' -f1)
cat <<EOF > manifest/vars-release-version.yml
releases:
- name: $RELEASE
  url: https://github.com/${GITHUB_REPO}/releases/download/v${version}/${RELEASE}-${version}.tgz
  version: $version
  sha1: $sha1
EOF
# Create a new tag and update the changes
echo "* Commiting git changes ..."
git add .final_builds releases/$RELEASE/index.yml "releases/$RELEASE/$RELEASE-$version.yml" config/blobs.yml manifest/vars-release-version.yml
git commit -m "$RELEASE v$version Boshrelease"
git push
git push --tags

description=$(cat <<EOF
# $RELEASE version $version

$DESCRIPTION

## Changes since last version

$git_changes

## Using in a bosh Deployment

    releases:
    - name: $RELEASE
      url: https://github.com/${GITHUB_REPO}/releases/download/v${version}/${RELEASE}-${version}.tgz
      version: $version
      sha1: $sha1
EOF
)
echo "* Creating a new release in Github ... "
printf -v DATA '{"tag_name": "v%s","target_commitish": "master","name": "v%s","body": %s,"draft": false, "prerelease": false}' "$version" "$version" "$(echo "$description" | $JQ -R -s '@text')"
releaseid=$($CURL -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" -XPOST --data "$DATA" "https://api.github.com/repos/$GITHUB_REPO/releases" | $JQ '.id')

# Upload the release
echo "* Uploading tarball to Github releases section ... "
echo -n "  URL: "
$CURL -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/octet-stream" --data-binary @"/tmp/$RELEASE-$$.tgz" "https://uploads.github.com/repos/$GITHUB_REPO/releases/$releaseid/assets?name=$RELEASE-$version.tgz" | $JQ -r '.browser_download_url'

# Delete the release
rm -f "/tmp/$RELEASE-$$.tgz"

if [ -n "$RELEASE_BUCKET" ]
then
    # Update ACLs on bucket
    echo "* Assigning public ACL to new blobs in bucket ... "
    $S3CMD setacl "s3://${RELEASE_BUCKET}" --acl-public --recursive
fi

echo
echo "*** Description https://github.com/$GITHUB_REPO/releases/tag/v$version: "
echo
echo "$description"
exit 0
