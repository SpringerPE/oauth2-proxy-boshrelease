# Oauth2-proxy Bosh release

This is a release based in https://github.com/bitly/oauth2_proxy
offering a reverse proxy that provides SSO authentication layer with Google,
Github or other provider. Nginx is doing HTTP Basic Auth once SSO authentication
is done againts Github, Google, etc. 

This release also ships with Nginx and Lua support allowing you to define
custom rules and lua programs to define complex rules againts APIs and backend.

Initially was created to provide an authentication layer with Google for Kibana.


# Developing

First of all, when do a git commit, try to use good commit messages; the release
changes on each release will be taken from the commit messages!

When you make changes in the packages (or add new ones), please use
`./update-blobs.sh` to sync and upload the new blobs. This script reads the `spec` file 
of every package or looks for a `prepare` script (inside the folder of each package):

* If there is a `packages/<package>/prepare`, it executes it and goes to the next package.
* If the spec file of a package in `packages/<package>/spec` has a key `files` with this
format `- folder/src.tgz   # url`, for example:
```
files:
- ruby-2.3/ruby-2.3.7.tar.gz      # https://cache.ruby-lang.org/pub/ruby/2.3/ruby-2.3.7.tar.gz
- ruby-2.3/rubygems-2.7.7.tgz     # https://rubygems.org/rubygems/rubygems-2.7.7.tgz
```
It will take the url, download the file to `blobs/ruby-2.3/ruby-2.3.7.tar.gz` and
it will run `bosh add-blob` with the new src "ruby-2.3.7.tar.gz". Take into
account the script does not download a package if there is a file with the same
name in the destination folder, so it the package was not properly downloaded
(e.g. script execution interrupted), please delete the destination folder and try
again.

The idea is make it easy to update the version of the packages. Making a `packaging`
script flexible, not linked to version, updating a package is just a matter of 
updating its `spec` file and run `./update-blobs.sh` and you have a new version
ready!. Extract of a ruby `packaging` script (just and example):
```
# Grab the latest versions that are in the directory
RUBY_VERSION=`ls -r ruby-2.3/ruby-* | sed 's/ruby-2.3\/ruby-\(.*\)\.tar\.gz/\1/' | head -1`
RUBYGEMS_VERSION=`ls -r ruby-2.3/rubygems-* | sed 's/ruby-2.3\/rubygems-\(.*\)\.tgz/\1/' | head -1`

echo "Extracting ruby-${RUBY_VERSION} ..."
tar xvf ruby-2.3/ruby-${RUBY_VERSION}.tar.gz

echo "Building ruby-${RUBY_VERSION} ..."
pushd ruby-${RUBY_VERSION}
  LDFLAGS="-Wl,-rpath -Wl,${BOSH_INSTALL_TARGET}" ./configure --prefix=${BOSH_INSTALL_TARGET} --disable-install-doc --with-opt-dir=${BOSH_INSTALL_TARGET}
  make
  make install
popd
```

The script does not process any args and it is safe to run as many times as you need
(take into account if you create `prepare` scrips!).


## Creating Dev releases (for testing)

To create a dev release -for testing purposes-, just run:

```
# Update or sync blobs
./update-blobs.sh
# Create a dev release
bosh  create-release --force --tarball=/tmp/release.tgz
# Upload release to bosh director
bosh -e <bosh-env> upload-release /tmp/release.tgz
```

Then you can modify your manifest to include `latest` as a version (no `url` and `sha` 
fields are needed when the release is manually uploaded): 

```
releases:
  [...]
- name: cf-logging
  version: latest
```

Once you know that the dev version is working, you can generate and publish a final
version of the release (see  below), and remember to change the deployment manifest
to use a url of the new final manifest like this:

```
releases:
  [...]
- name: oauth2-proxy
  url: https://github.com/SpringerPE/oauth2-proxy-boshrelease/releases/download/v1/oauth2-proxy-1.tgz
  version: 1
  sha1: 12c34892f5bc99491c310c8867b508f1bc12629c
```

or much better, use an operations file ;-)



## Creating a new final release and publishing to GitHub releases:

Run: `./create-final-public-release.sh [version-number]`

Keep in mind you will need a Github token defined in a environment variable `GITHUB_TOKEN`.
Please get your token here: https://help.github.com/articles/creating-an-access-token-for-command-line-use/
and run `export GITHUB_TOKEN="xxxxxxxxxxxxxxxxx"`, after that you can use the script.

`version-number` is optional. If not provided it will create a new major version
(as integer), otherwise you can specify versions like "8.1", "8.1.2". There is a
regular expresion in the script to check if the format is correct. Bosh client
does not allow you to create 2 releases with the same version number. If for some
reason you need to recreate a release version, delete the file created in 
`releases/oauth2-proxy-boshrelease` and update the index file in the same location,
you also need to remove the release (and tags) in Github.



# Deploying with operations files:


For example to deploy the base manifest (`manifest` folder):
 

```
bosh -d logstash deploy oauth2-proxy.yml \
    -o operations/add-release-version.yml  --vars-file vars-release-version.yml \
    -o operations/add-iaas-parameters.yml  --vars-file vars-iaas-parameters.yml
```


Be aware you need to define this secrets in Credhub:

```
# oauth2_proxy
oauth2_proxy-client_id: xxxxxxxxxxxxxxxxxxxxxxxxxxx
oauth2_proxy-client_secret: xxxxxxxxxxxxxxxxxxxxxxxxxx
oauth2_proxy-cookie_secret: xxxxxxxxxxxxxxxxxxxxxx
oauth2_proxy-domains: [ hola.com, example.com ]
oauth2_proxy-url: "http://kibana.example.com"
oauth2_proxy-upstream: "http://external-kibana.com:8080"
# "bmdpbng6c2VjcmV0cGFzc3dvcmQ="is a base64 encoded string of my service account 's credentials "nginx:secretpassword"
oauth2_proxy-upstream-basic-auth: "Basic bmdpbng6c2VjcmV0cGFzc3dvcmQ="
```


# Author


SpringerNature Platform Engineering

José Riguera López (jose.riguera@springer.com)


# License

Apache 2.0 License
